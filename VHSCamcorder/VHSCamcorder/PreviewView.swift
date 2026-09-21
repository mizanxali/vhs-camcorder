import AVFoundation
import SwiftUI

/// Hosts the AVSampleBufferDisplayLayer that CameraSession enqueues frames into.
struct PreviewView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let onLayout: () -> Void

    func makeUIView(context: Context) -> DisplayView {
        let view = DisplayView()
        layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        view.onLayout = onLayout
        return view
    }

    func updateUIView(_ uiView: DisplayView, context: Context) {}

    final class DisplayView: UIView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.first?.frame = bounds
            onLayout?()
        }
    }
}
