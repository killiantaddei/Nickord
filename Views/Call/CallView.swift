import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - CallView

struct CallView: View {
    let friend: NickordUser
    let isVideo: Bool
    var signalID: String?

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var callState: CallState = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var showInviteSheet = false
    @State private var invitedFriendIDs: Set<String> = []
    @State private var isMuted = false
    @State private var isSpeakerOn = false
    @State private var isCameraEnabled = true
    @State private var pulseAnimation = false
    @StateObject private var cameraService = CameraService()
    private let audioSession = AVAudioSession.sharedInstance()

    enum CallState {
        case connecting, active, ended
    }

    private var inviteCandidates: [NickordUser] {
        guard let currentUser = authVM.currentUser else { return [] }
        return LocalDataStore.shared
            .usersByIDs(currentUser.friends)
            .filter { $0.id != friend.id }
    }

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .onAppear {
            setupAudio()
            if isVideo {
                cameraService.start()
                isCameraEnabled = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(response: 0.5)) {
                    callState = .active
                    startTimer()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            cameraService.stop()
            try? audioSession.setActive(false)
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if isVideo {
            CameraPreview(session: cameraService.session)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.6),
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#0A0E27"),
                        Color(hex: "#1A1040"),
                        Color(hex: "#0D1B2A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(
                            Theme.primary.opacity(0.08 - Double(i) * 0.02),
                            lineWidth: 1.5
                        )
                        .frame(
                            width: pulseAnimation ? CGFloat(200 + i * 80) : CGFloat(140 + i * 80),
                            height: pulseAnimation ? CGFloat(200 + i * 80) : CGFloat(140 + i * 80)
                        )
                        .animation(
                            .easeInOut(duration: 2.0 + Double(i) * 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.3),
                            value: pulseAnimation
                        )
                }

                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(Theme.primary.opacity(0.12))
                        .frame(width: CGFloat(4 + i * 2), height: CGFloat(4 + i * 2))
                        .offset(
                            x: pulseAnimation ? CGFloat(30 + i * 20) : CGFloat(-30 - i * 20),
                            y: pulseAnimation ? CGFloat(-50 + i * 25) : CGFloat(50 - i * 25)
                        )
                        .animation(
                            .easeInOut(duration: 3.0 + Double(i) * 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                            value: pulseAnimation
                        )
                }
            }
        }
    }

    // MARK: - Content

    private var contentLayer: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: hangUp) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(isVideo ? "Videochiamata" : "Chiamata vocale")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    if callState == .active {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.online)
                                .frame(width: 6, height: 6)
                            Text(timeString)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }

                Spacer()

                Button {
                    isSpeakerOn.toggle()
                } label: {
                    Image(systemName: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill")
                        .font(.body)
                        .foregroundColor(isSpeakerOn ? Theme.primary : .white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(isSpeakerOn ? Theme.primary.opacity(0.2) : Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    if callState == .connecting {
                        Circle()
                            .stroke(Theme.primary.opacity(0.3), lineWidth: 3)
                            .frame(width: pulseAnimation ? 140 : 120, height: pulseAnimation ? 140 : 120)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )

                        Circle()
                            .stroke(Theme.primary.opacity(0.15), lineWidth: 2)
                            .frame(width: pulseAnimation ? 170 : 145, height: pulseAnimation ? 170 : 145)
                            .animation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                    }

                    if callState == .active {
                        Circle()
                            .stroke(Theme.online.opacity(0.25), lineWidth: 2)
                            .frame(width: 130, height: 130)
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.primary, Theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .shadow(color: Theme.primary.opacity(0.4), radius: 20, x: 0, y: 8)
                        .overlay(
                            Text(String(friend.username.prefix(1)).uppercased())
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                }

                Text(friend.username)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer()

            VStack(spacing: 20) {
                if isVideo {
                    videoControls
                } else {
                    audioControls
                }

                Button(action: hangUp) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.down.fill")
                            .font(.title3)
                        Text("Termina")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(width: 160, height: 56)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .shadow(color: Color.red.opacity(0.4), radius: 12, x: 0, y: 6)
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Audio Controls

    private var audioControls: some View {
        HStack(spacing: 20) {
            callControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                label: isMuted ? "Attiva" : "Muto",
                isActive: isMuted,
                activeColor: .orange
            ) {
                toggleMute()
            }

            callControlButton(
                icon: "person.badge.plus.fill",
                label: "Invita",
                isActive: false,
                activeColor: Theme.primary
            ) {
                showInviteSheet = true
            }

            callControlButton(
                icon: "video.fill",
                label: "Video",
                isActive: false,
                activeColor: Theme.primary
            ) {
                // Placeholder
            }
        }
    }

    // MARK: - Video Controls

    private var videoControls: some View {
        HStack(spacing: 16) {
            callControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                label: isMuted ? "Attiva" : "Muto",
                isActive: isMuted,
                activeColor: .orange
            ) {
                toggleMute()
            }

            callControlButton(
                icon: isCameraEnabled ? "video.fill" : "video.slash.fill",
                label: isCameraEnabled ? "Camera" : "Camera off",
                isActive: !isCameraEnabled,
                activeColor: .orange
            ) {
                toggleCamera()
            }

            callControlButton(
                icon: "camera.rotate.fill",
                label: "Ruota",
                isActive: false,
                activeColor: Theme.primary
            ) {
                cameraService.switchCamera()
            }
            .disabled(!isCameraEnabled)
            .opacity(isCameraEnabled ? 1 : 0.4)

            callControlButton(
                icon: "person.badge.plus.fill",
                label: "Invita",
                isActive: false,
                activeColor: Theme.primary
            ) {
                showInviteSheet = true
            }
        }
    }

    // MARK: - Control Button

    private func callControlButton(
        icon: String,
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isActive ? activeColor : .white)
                    .frame(width: 56, height: 56)
                    .background(
                        isActive
                            ? activeColor.opacity(0.2)
                            : Color.white.opacity(0.1)
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isActive ? activeColor.opacity(0.4) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )

                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Status

    private var statusText: String {
        switch callState {
        case .connecting: return "Connessione in corso..."
        case .active: return isVideo ? "Videochiamata attiva" : "In chiamata"
        case .ended: return "Chiamata terminata"
        }
    }

    private var statusColor: Color {
        switch callState {
        case .connecting: return .orange
        case .active: return Theme.online
        case .ended: return .red
        }
    }

    private var timeString: String {
        let m = callDuration / 60
        let s = callDuration % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func hangUp() {
        callState = .ended
        dismiss()
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            callDuration += 1
        }
    }

    // MARK: - Audio

    private func setupAudio() {
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try? audioSession.setActive(true)
    }

    private func toggleMute() {
        isMuted.toggle()
        if isMuted {
            try? audioSession.setCategory(.playback, mode: .voiceChat, options: [.defaultToSpeaker])
        } else {
            try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        }
        try? audioSession.setActive(true)
    }

    private func toggleCamera() {
        guard isVideo else { return }
        isCameraEnabled.toggle()
        if isCameraEnabled {
            cameraService.start()
        } else {
            cameraService.stop()
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if inviteCandidates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.textSecondary)
                        Text("Nessun amico disponibile da invitare")
                            .foregroundColor(Theme.textSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(inviteCandidates) { candidate in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Theme.surfaceElevated)
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Text(String(candidate.username.prefix(1)).uppercased())
                                                .font(.headline.bold())
                                                .foregroundColor(.white)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.username)
                                            .foregroundColor(.white)
                                            .font(.subheadline.bold())
                                        Text(candidate.isOnline ? "Online" : "Offline")
                                            .font(.caption)
                                            .foregroundColor(candidate.isOnline ? Theme.online : Theme.textSecondary)
                                    }
                                    Spacer()
                                    Button {
                                        if let id = candidate.id {
                                            invitedFriendIDs.insert(id)
                                        }
                                    } label: {
                                        Text(invitedFriendIDs.contains(candidate.id ?? "") ? "Invitato" : "Invita")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                invitedFriendIDs.contains(candidate.id ?? "")
                                                    ? Theme.online
                                                    : Theme.primary
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .disabled(invitedFriendIDs.contains(candidate.id ?? ""))
                                }
                                .padding()
                                .glassCard(cornerRadius: 14, opacity: 0.1)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Invita amici")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { showInviteSheet = false }
                        .foregroundColor(Theme.primary)
                }
            }
        }
    }
}

final class CameraService: ObservableObject {
    let session = AVCaptureSession()
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .front

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self, granted else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                }
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        isConfigured = true
    }

    func switchCamera() {
        let next: AVCaptureDevice.Position = currentPosition == .front ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        guard session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        currentPosition = next
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
