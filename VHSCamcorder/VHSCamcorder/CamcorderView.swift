import AVFoundation
import SwiftUI

struct CamcorderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraSession()
    @State private var isRecording = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewView(layer: camera.displayLayer, onLayout: camera.updateRotation)
                .aspectRatio(4 / 3, contentMode: .fit)
        }
        .overlay(alignment: .trailing) {
            recordButton.padding(.trailing, 24)
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            await camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)) { _ in stop() }
    }

    private var recordButton: some View {
        Button {
            if isRecording { stop() } else { Task { isRecording = await camera.startRecording() } }
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 72, height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: isRecording ? 8 : 30)
                        .fill(.red)
                        .frame(width: isRecording ? 32 : 60, height: isRecording ? 32 : 60)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }

    private func stop() {
        guard isRecording else { return }
        camera.stopRecording()
        isRecording = false
    }
}
