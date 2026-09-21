import AVFoundation
import SwiftUI

/// Hosts the AVSampleBufferDisplayLayer that CameraSession enqueues frames into.
struct PreviewView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> DisplayView {
        let view = DisplayView()
        layer.videoGravity = .resizeAspect
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: DisplayView, context: Context) {}

    final class DisplayView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.first?.frame = bounds
        }
    }
}
