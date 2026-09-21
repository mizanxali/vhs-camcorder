import AVFoundation
import Photos

/// One recording: H.264 + AAC into a temp .mov, then saved to Photos. Used only from the camera queue.
nonisolated final class VideoRecorder: @unchecked Sendable {
    private let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private(set) var startTime: CMTime?

    init(videoSettings: [String: Any], audioSettings: [String: Any]) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audio.expectsMediaDataInRealTime = true
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    func append(video pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if startTime == nil {
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        guard video.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    func append(audio sampleBuffer: CMSampleBuffer) {
        guard startTime != nil, audio.isReadyForMoreMediaData else { return }
        audio.append(sampleBuffer)
    }

    func finish() async {
        guard startTime != nil else {
            writer.cancelWriting()
            return
        }
        video.markAsFinished()
        audio.markAsFinished()
        await writer.finishWriting()
        if writer.status == .completed {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.url)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}
