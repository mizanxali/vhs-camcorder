import CoreImage
import UIKit

/// Draws the camcorder OSD (REC/STBY, counter, date) as a transparent CIImage. Cached per displayed second.
nonisolated final class OverlayRenderer {
    private var cached: (key: String, image: CIImage)?

    private static let font: UIFont = {
        if let url = Bundle.main.url(forResource: "VCR OSD Mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return UIFont(name: "VCROSDMono", size: 52) ?? .monospacedSystemFont(ofSize: 48, weight: .bold)
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM. d yyyy"
        return f
    }()

    /// `elapsed` is nil when idle, otherwise seconds since recording started.
    func image(elapsed: TimeInterval?, size: CGSize) -> CIImage {
        let seconds = Int(elapsed ?? 0)
        let recording = elapsed != nil
        let date = Self.dateFormatter.string(from: Date()).uppercased()
        let key = "\(recording)|\(seconds)|\(date)|\(size)"
        if let cached, cached.key == key { return cached.image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let font = Self.font
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
            shadow.shadowOffset = CGSize(width: 3, height: 3)
            let white: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .shadow: shadow]
            let red: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.red, .shadow: shadow]
            let margin: CGFloat = 60

            // Top-left: blinking red dot + REC while recording, STBY when idle.
            let status = NSMutableAttributedString()
            if recording {
                status.append(NSAttributedString(string: seconds % 2 == 0 ? "● " : "   ", attributes: red))
                status.append(NSAttributedString(string: "REC", attributes: white))
            } else {
                status.append(NSAttributedString(string: "STBY", attributes: white))
            }
            status.draw(at: CGPoint(x: margin, y: margin))

            // Top-right: counter.
            let counter = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) as NSString
            let counterSize = counter.size(withAttributes: white)
            counter.draw(at: CGPoint(x: size.width - margin - counterSize.width, y: margin), withAttributes: white)

            // Bottom-right: date.
            let dateSize = (date as NSString).size(withAttributes: white)
            (date as NSString).draw(at: CGPoint(x: size.width - margin - dateSize.width, y: size.height - margin - dateSize.height), withAttributes: white)
        }

        let image = CIImage(cgImage: rendered.cgImage!)
        cached = (key, image)
        return image
    }
}
