import AVFoundation
import SwiftUI

struct CamcorderView: View {
    private static let plastic = Color(red: 0.13, green: 0.12, blue: 0.11)
    private static let plasticDark = Color(red: 0.06, green: 0.055, blue: 0.05)
    private static let label = Color(red: 0.82, green: 0.76, blue: 0.64)
    private static let maroon = Color(red: 0.5, green: 0.11, blue: 0.09)
    private static let recRed = Color(red: 0.82, green: 0.16, blue: 0.1)

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraSession()
    @State private var isRecording = false
    @State private var toast: String?
    @State private var zoom: CGFloat = 1
    @State private var zoomRange: ClosedRange<CGFloat> = 1...1
    @State private var hasTorch = false
    @State private var torchOn = false
    @State private var pinchBase: CGFloat?
    @State private var flash = false
    @State private var lastShot: UIImage?
    private static let zoomPresets: [CGFloat] = [0.5, 1, 2, 3]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.plastic, Self.plasticDark], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            viewfinder
        }
        .overlay(alignment: .leading) { leftPanel.padding(.leading, 28) }
        .overlay(alignment: .trailing) { rightPanel.padding(.trailing, 28) }
        .overlay(alignment: .top) { toastView.padding(.top, 16) }
        .overlay(alignment: .bottomLeading) { thumbnail.padding(.leading, 28).padding(.bottom, 16) }
        .sensoryFeedback(.impact, trigger: isRecording)
        .sensoryFeedback(.impact(weight: .light), trigger: flash) { _, new in new }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                camera.follow(scene)
            }
            apply(await camera.start())
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
            .overlay(Color.white.opacity(flash ? 0.85 : 0).animation(flash ? nil : .easeOut(duration: 0.25), value: flash))
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
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? zoom
                        pinchBase = base
                        zoom = min(max(base * value.magnification, zoomRange.lowerBound), zoomRange.upperBound)
                        camera.setZoom(zoom)
                    }
                    .onEnded { _ in pinchBase = nil }
            )

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
            zoomColumn
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 32) {
            shutterButton
            Button(action: capturePhoto) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Self.label.opacity(0.6))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(red: 0.1, green: 0.095, blue: 0.09)))
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1.5))
            }
            .buttonStyle(ShutterStyle())
            Button {
                Task { apply(await camera.flipCamera()) }
            } label: {
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

            if hasTorch {
                Button {
                    torchOn.toggle()
                    camera.setTorch(torchOn)
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(torchOn ? Color(red: 0.95, green: 0.75, blue: 0.35) : Self.label.opacity(0.6))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color(red: 0.1, green: 0.095, blue: 0.09)))
                        .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1.5))
                }
                .buttonStyle(ShutterStyle())
            }
        }
    }

    /// Resets per-camera UI state after start or flip.
    private func apply(_ capabilities: CameraSession.Capabilities) {
        zoomRange = capabilities.zoomRange
        hasTorch = capabilities.hasTorch
        zoom = 1
        torchOn = false
    }

    // MARK: Zoom

    private var zoomColumn: some View {
        let presets = Self.zoomPresets.filter { zoomRange.contains($0) }
        let active = presets.last { $0 <= zoom + 0.01 } ?? presets.first
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(presets, id: \.self) { preset in
                let isActive = preset == active
                Button {
                    zoom = preset
                    camera.setZoom(preset, ramped: true)
                } label: {
                    Text(isActive ? Self.zoomLabel(zoom) : Self.zoomLabel(preset))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? Self.label : Self.label.opacity(0.4))
                        .frame(width: 44, height: 26)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(isActive ? 0.6 : 0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Self.label.opacity(isActive ? 0.35 : 0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(presets.count > 1 ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    private static func zoomLabel(_ factor: CGFloat) -> String {
        (factor.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(factor)) : String(format: "%.1f", factor)) + "x"
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

    // MARK: Last shot

    private var thumbnail: some View {
        Group {
            if let lastShot {
                Button {
                    openURL(URL(string: "photos-redirect://")!)
                } label: {
                    Image(uiImage: lastShot)
                        .resizable()
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(width: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Self.label.opacity(0.35), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                }
                .buttonStyle(ShutterStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: lastShot)
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
        Task { saved(await camera.stopRecording(), "SAVED TO PHOTOS") }
    }

    private func capturePhoto() {
        guard !flash else { return }
        flash = true
        Task {
            let shot = await camera.capturePhoto()
            flash = false
            saved(shot, "PHOTO SAVED")
        }
    }

    private func saved(_ thumbnail: UIImage?, _ message: String) {
        if let thumbnail { lastShot = thumbnail }
        show(thumbnail != nil ? message : "SAVE FAILED")
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
