import SwiftUI

struct CamcorderView: View {
    @State private var camera = CameraSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewView(layer: camera.displayLayer, onLayout: camera.updateRotation)
                .aspectRatio(4 / 3, contentMode: .fit)
        }
        .task { await camera.start() }
    }
}
