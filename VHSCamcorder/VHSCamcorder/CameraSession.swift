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
    private var device: AVCaptureDevice?                      // queue only, current video device
    private var wideFactor: CGFloat = 1                       // queue only, videoZoomFactor that displays as 1x
    @MainActor private var geometryObservation: NSKeyValueObservation?

    @MainActor override init() {
        displayLayer = AVSampleBufferDisplayLayer()
        renderer = displayLayer.sampleBufferRenderer
        super.init()
    }

    struct Capabilities: Sendable {
        var zoomRange: ClosedRange<CGFloat> = 1...1   // display factors, 1 = the main wide lens
        var hasTorch = false
    }

    /// Queue only.
    private var capabilities: Capabilities {
        Capabilities(zoomRange: zoomRange, hasTorch: device?.hasTorch ?? false)
    }

    func start() async -> Capabilities {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return Capabilities() }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return await onQueue {
            self.configure()
            self.session.startRunning()
            return self.capabilities
        }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
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
    /// Prefers the virtual multi-lens device so zoom covers ultra-wide through telephoto with automatic lens switching.
    private func addCamera(_ position: AVCaptureDevice.Position) -> Bool {
        let preferred: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: preferred, mediaType: .video, position: position).devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
            .forEach(session.removeInput)
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        wideFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.videoZoomFactor = wideFactor
            device.unlockForConfiguration()
        }
        self.device = device
        self.position = position
        return true
    }

    func flipCamera() async -> Capabilities {
        await onQueue {
            self.session.beginConfiguration()
            _ = self.addCamera(self.position == .back ? .front : .back)
            self.session.commitConfiguration()
            self.applyRotation()
            return self.capabilities
        }
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    // MARK: Zoom

    /// Queue only. Display factors: 1 = main wide lens, 0.5 = ultra-wide. Digital zoom capped at 10x.
    private var zoomRange: ClosedRange<CGFloat> {
        guard let device else { return 1...1 }
        let lower = device.minAvailableVideoZoomFactor / wideFactor
        let upper = min(device.maxAvailableVideoZoomFactor, wideFactor * 10) / wideFactor
        return lower...max(lower, upper)
    }

    /// `ramped` glides to the factor (presets); otherwise it snaps (pinch).
    func setZoom(_ display: CGFloat, ramped: Bool = false) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let range = self.zoomRange
            let factor = min(max(display, range.lowerBound), range.upperBound) * self.wideFactor
            if ramped {
                device.ramp(toVideoZoomFactor: factor, withRate: 6)
            } else {
                device.videoZoomFactor = factor
            }
            device.unlockForConfiguration()
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

    /// Finalizes the clip and returns true once it is saved to Photos.
    func stopRecording() async -> Bool {
        let recorder: VideoRecorder? = queue.sync {
            defer { self.recorder = nil }
            return self.recorder
        }
        guard let recorder else { return false }
        return await recorder.finish()
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
