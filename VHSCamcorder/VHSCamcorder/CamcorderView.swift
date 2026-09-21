import AVFoundation
import SwiftUI

struct CamcorderView: View {
    private static let plastic = Color(red: 0.13, green: 0.12, blue: 0.11)
    private static let plasticDark = Color(red: 0.06, green: 0.055, blue: 0.05)
    private static let label = Color(red: 0.82, green: 0.76, blue: 0.64)
    private static let maroon = Color(red: 0.5, green: 0.11, blue: 0.09)
    private static let recRed = Color(red: 0.82, green: 0.16, blue: 0.1)

    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraSession()
    @State private var isRecording = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.plastic, Self.plasticDark], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            viewfinder
        }
        .overlay(alignment: .leading) { leftPanel.padding(.leading, 28) }
        .overlay(alignment: .trailing) { rightPanel.padding(.trailing, 28) }
        .overlay(alignment: .bottom) { toastView.padding(.bottom, 20) }
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

    // MARK: Housing

    private var viewfinder: some View {
        PreviewView(layer: camera.displayLayer)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.85), lineWidth: 3)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.09, green: 0.085, blue: 0.08)))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
            .padding(.vertical, 12)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRecording ? Self.recRed : Color(red: 0.2, green: 0.06, blue: 0.05))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                    .shadow(color: Self.recRed.opacity(isRecording ? 0.7 : 0), radius: 4)
                Text("REC").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Self.label.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("VHS")
                    .font(.system(size: 22, weight: .heavy).width(.condensed))
                    .foregroundStyle(Self.label.opacity(0.32))
                Text("VIDEO HI-FI")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Self.label.opacity(0.28))
            }
            VStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule().fill(.black.opacity(0.35)).frame(width: 40, height: 2)
                        .overlay(alignment: .bottom) { Capsule().fill(.white.opacity(0.04)).frame(height: 1) }
                }
            }
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 32) {
            shutterButton
            Button(action: camera.flipCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Self.label.opacity(0.6))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(red: 0.1, green: 0.095, blue: 0.09)))
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1.5))
            }
            .buttonStyle(ShutterStyle())
            .disabled(isRecording)
            .opacity(isRecording ? 0.3 : 1)
        }
    }

    // MARK: Shutter

    private var shutterButton: some View {
        Button {
            if isRecording { stop() } else { Task { isRecording = await camera.startRecording() } }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.095, blue: 0.09))
                    .frame(width: 84, height: 84)
                    .overlay(Circle().strokeBorder(.black.opacity(0.8), lineWidth: 2))
                    .overlay(Circle().strokeBorder(.white.opacity(0.05), lineWidth: 1).padding(2))
                RoundedRectangle(cornerRadius: isRecording ? 6 : 28)
                    .fill(LinearGradient(colors: [isRecording ? Self.recRed : Self.maroon, (isRecording ? Self.recRed : Self.maroon).opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(width: isRecording ? 28 : 56, height: isRecording ? 28 : 56)
                    .overlay(RoundedRectangle(cornerRadius: isRecording ? 6 : 28).strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
                    .opacity(isRecording ? 0.6 : 1)
                    .animation(isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .easeInOut(duration: 0.15), value: isRecording)
            }
        }
        .buttonStyle(ShutterStyle())
    }

    private struct ShutterStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    // MARK: Toast

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.label)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .overlay(Capsule().strokeBorder(Self.label.opacity(0.2), lineWidth: 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        Task {
            toast = await camera.stopRecording() ? "SAVED TO PHOTOS" : "SAVE FAILED"
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }
}
