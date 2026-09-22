import CoreImage
import CoreVideo
import ImageIO
import QuartzCore
import UIKit

/// Turns a raw camera frame into the VHS output frame (4:3 landscape or 3:4 portrait). Rendered once per frame into a pooled buffer.
nonisolated final class VHSFilter {
    static let landscape = CGSize(width: 1440, height: 1080)
    static let portrait = CGSize(width: 1080, height: 1440)
    /// Set from the camera queue when the interface rotates; frames of any size are aspect-filled into it.
    var outputSize = landscape

    private let context = CIContext()
    private let kernel: CIKernel
    private let startTime = CACurrentMediaTime()
    private var pool: (size: CGSize, pool: CVPixelBufferPool)?
    private let overlay = OverlayRenderer()

    init() {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        kernel = try! CIKernel(functionName: "vhs", fromMetalLibraryData: Data(contentsOf: url))
    }

    /// `elapsed` is nil when idle, otherwise seconds since recording started (drives the REC overlay).
    func render(_ input: CVPixelBuffer, elapsed: TimeInterval?) -> CVPixelBuffer? {
        let size = outputSize
        let source = CIImage(cvPixelBuffer: input)
        let scale = max(size.width / source.extent.width, size.height / source.extent.height)
        let scaled = source.transformed(by: .init(scaleX: scale, y: scale))
        let crop = CGPoint(x: (scaled.extent.width - size.width) / 2, y: (scaled.extent.height - size.height) / 2)
        let cropped = scaled
            .cropped(to: CGRect(origin: crop, size: size))
            .transformed(by: .init(translationX: -crop.x, y: -crop.y))
        let composed = overlay.image(elapsed: elapsed, size: size)
            .composited(over: cropped)
            .clampedToExtent()

        let extent = CGRect(origin: .zero, size: size)
        guard let image = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -80, dy: -2) },
            arguments: [composed, Float(CACurrentMediaTime() - startTime), Float(extent.width), Float(extent.height)]
        ), let output = makeBuffer(size) else { return nil }
        context.render(image, to: output)
        return output
    }

    /// JPEG of a frame this filter rendered, for stills.
    func jpeg(_ buffer: CVPixelBuffer) -> Data? {
        context.jpegRepresentation(
            of: CIImage(cvPixelBuffer: buffer),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9]
        )
    }

    /// 240x180 preview of a rendered frame, for the last-clip thumbnail.
    func thumbnail(_ buffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: .init(scaleX: 1 / 6, y: 1 / 6))
        return context.createCGImage(image, from: image.extent).map { UIImage(cgImage: $0) }
    }

    private func makeBuffer(_ size: CGSize) -> CVPixelBuffer? {
        if pool?.size != size {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &created)
            pool = created.map { (size, $0) }
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool.pool, &buffer)
        return buffer
    }
}
