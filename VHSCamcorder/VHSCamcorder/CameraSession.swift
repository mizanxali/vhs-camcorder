import AVFoundation
import Photos
import UIKit

/// Owns the capture session. Every video frame is rendered once by VHSFilter, shown in `displayLayer`,
/// and appended to the active recorder if there is one.
nonisolated final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let displayLayer: AVSampleBufferDisplayLayer
    private let renderer: AVSampleBufferVideoRenderer

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "camera.frames")
    private let filter = VHSFilter()
    private var recorder: VideoRecorder?   // touched only on `queue`
    private var position: AVCaptureDevice.Position = .back   // queue only
    private var rotationAngle: CGFloat = 0                    // queue only, for the back camera
    @MainActor private var geometryObservation: NSKeyValueObservation?

    @MainActor override init() {
        displayLayer = AVSampleBufferDisplayLayer()
        renderer = displayLayer.sampleBufferRenderer
        super.init()
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        queue.async {
            self.configure()
            self.session.startRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard addCamera(position) else { return }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput), session.canAddOutput(audioOutput) {
            session.addInput(micInput)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }
    }

    /// Replaces the video input with the camera at `position`, locked to 30fps. Caller holds beginConfiguration.
    private func addCamera(_ position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
            .forEach(session.removeInput)
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
        self.position = position
        return true
    }

    func flipCamera() {
        queue.async {
            self.session.beginConfiguration()
            _ = self.addCamera(self.position == .back ? .front : .back)
            self.session.commitConfiguration()
            self.applyRotation()
        }
    }

    /// Keeps captured frames upright by following the scene's interface orientation (landscape only).
    @MainActor func follow(_ scene: UIWindowScene) {
        geometryObservation = scene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] scene, _ in
            let orientation = MainActor.assumeIsolated { scene.effectiveGeometry.interfaceOrientation }
            self?.queue.async {
                self?.rotationAngle = orientation == .landscapeLeft ? 180 : 0
                self?.applyRotation()
            }
        }
    }

    /// Queue only. The connection is recreated on every input change, so this runs after flips too.
    private func applyRotation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        // The front sensor is mounted 180° from the back one.
        let angle = position == .front ? 180 - rotationAngle : rotationAngle
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = position == .front
    }

    // MARK: Recording

    /// Returns false if Photos access was refused, in which case nothing is recorded.
    func startRecording() async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return false }
        queue.async {
            guard self.recorder == nil,
                  var videoSettings = self.videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov),
                  let audioSettings = self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) else { return }
            videoSettings[AVVideoWidthKey] = Int(VHSFilter.outputSize.width)
            videoSettings[AVVideoHeightKey] = Int(VHSFilter.outputSize.height)
            self.recorder = try? VideoRecorder(videoSettings: videoSettings, audioSettings: audioSettings)
        }
        return true
    }

    func stopRecording() {
        queue.async {
            guard let recorder = self.recorder else { return }
            self.recorder = nil
            Task { await recorder.finish() }
        }
    }

    // MARK: Capture callbacks (on `queue`)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === videoOutput else {
            recorder?.append(audio: sampleBuffer)
            return
        }
        let time = sampleBuffer.presentationTimeStamp
        let elapsed = recorder.map { $0.startTime.map { time.seconds - $0.seconds } ?? 0 }
        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let rendered = filter.render(pixelBuffer, elapsed: elapsed),
              let display = try? CMSampleBuffer(
                imageBuffer: rendered,
                formatDescription: CMVideoFormatDescription(imageBuffer: rendered),
                sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
              ) else { return }
        recorder?.append(video: rendered, at: time)

        display.sampleAttachments[0][.displayImmediately] = true
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(display)
    }
}
