import CoreImage
import CoreVideo
import QuartzCore

/// Turns a raw camera frame into the 4:3 VHS output frame. Rendered once per frame into a pooled buffer.
nonisolated final class VHSFilter {
    static let outputSize = CGSize(width: 1440, height: 1080)

    private let context = CIContext()
    private let kernel: CIKernel
    private let startTime = CACurrentMediaTime()
    private var pool: CVPixelBufferPool?

    init() {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        kernel = try! CIKernel(functionName: "vhs", fromMetalLibraryData: Data(contentsOf: url))
    }

    func render(_ input: CVPixelBuffer) -> CVPixelBuffer? {
        let source = CIImage(cvPixelBuffer: input)
        let scale = Self.outputSize.height / source.extent.height
        let scaled = source.transformed(by: .init(scaleX: scale, y: scale))
        let cropX = (scaled.extent.width - Self.outputSize.width) / 2
        let cropped = scaled
            .cropped(to: CGRect(origin: CGPoint(x: cropX, y: 0), size: Self.outputSize))
            .transformed(by: .init(translationX: -cropX, y: 0))
            .clampedToExtent()

        let extent = CGRect(origin: .zero, size: Self.outputSize)
        guard let image = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -80, dy: -2) },
            arguments: [cropped, Float(CACurrentMediaTime() - startTime), Float(extent.width), Float(extent.height)]
        ), let output = makeBuffer() else { return nil }
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
