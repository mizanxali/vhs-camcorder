import CoreImage
import CoreVideo

/// Turns a raw camera frame into the 4:3 output frame. Phase 1: crop only, shader comes in phase 2.
nonisolated final class VHSFilter {
    static let outputSize = CGSize(width: 1440, height: 1080)

    private let context = CIContext()
    private var pool: CVPixelBufferPool?

    func render(_ input: CVPixelBuffer) -> CVPixelBuffer? {
        let source = CIImage(cvPixelBuffer: input)
        let scale = Self.outputSize.height / source.extent.height
        let scaled = source.transformed(by: .init(scaleX: scale, y: scale))
        let cropX = (scaled.extent.width - Self.outputSize.width) / 2
        let image = scaled
            .cropped(to: CGRect(origin: CGPoint(x: cropX, y: 0), size: Self.outputSize))
            .transformed(by: .init(translationX: -cropX, y: 0))

        guard let output = makeBuffer() else { return nil }
        context.render(image, to: output)
        return output
    }

    private func makeBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(Self.outputSize.width),
                kCVPixelBufferHeightKey as String: Int(Self.outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
