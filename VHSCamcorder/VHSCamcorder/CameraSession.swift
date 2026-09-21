import AVFoundation
import UIKit

/// Owns the capture session. Every frame is rendered once by VHSFilter and enqueued to `displayLayer`.
nonisolated final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let displayLayer: AVSampleBufferDisplayLayer
    private let renderer: AVSampleBufferVideoRenderer

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames")
    private let filter = VHSFilter()

    @MainActor override init() {
        displayLayer = AVSampleBufferDisplayLayer()
        renderer = displayLayer.sampleBufferRenderer
        super.init()
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        queue.async {
            self.configure()
            self.session.startRunning()
        }
        await updateRotation()
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)
    }

    /// Keeps captured frames upright in whichever landscape orientation the phone is held. Call after layout.
    @MainActor func updateRotation() {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.effectiveGeometry.interfaceOrientation }
            .first ?? .landscapeRight
        let angle: CGFloat = orientation == .landscapeLeft ? 180 : 0
        queue.async {
            guard let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let rendered = filter.render(pixelBuffer),
              let display = try? CMSampleBuffer(
                imageBuffer: rendered,
                formatDescription: CMVideoFormatDescription(imageBuffer: rendered),
                sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: sampleBuffer.presentationTimeStamp, decodeTimeStamp: .invalid)
              ) else { return }
        display.sampleAttachments[0][.displayImmediately] = true

        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(display)
    }
}
