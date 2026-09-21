import AVFoundation
import SwiftUI

struct CamcorderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraSession()
    @State private var isRecording = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewView(layer: camera.displayLayer)
                .aspectRatio(4 / 3, contentMode: .fit)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 32) {
                recordButton
                flipButton
            }
            .padding(.trailing, 24)
        }
        .sensoryFeedback(.impact, trigger: isRecording)
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                camera.follow(scene)
            }
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

    private var flipButton: some View {
        Button(action: camera.flipCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(isRecording)
        .opacity(isRecording ? 0.3 : 1)
    }

    private func stop() {
        guard isRecording else { return }
        camera.stopRecording()
        isRecording = false
    }
}
