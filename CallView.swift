import SwiftUI
import AVFoundation
import UIKit
import WebRTC
import Combine

// MARK: - CallView

struct CallView: View {
    let friend: NickordUser
    let isVideo: Bool
    var signalID: String?
    var isCaller: Bool = true

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var callState: CallState = .connecting
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var showInviteSheet = false
    @State private var invitedFriendIDs: Set<String> = []
    @State private var isMuted = false
    @State private var isSpeakerOn = true
    @State private var isCameraEnabled = true
    @State private var pulseAnimation = false
    @State private var didStartRTC = false
    @State private var callSignalListener: SubscriptionHandle?
    @State private var rtcManager: WebRTCCallManager?

    private let audioSession = AVAudioSession.sharedInstance()
    private let dataService = DataService.shared

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
        .onAppear(perform: startCallLifecycle)
        .onDisappear(perform: cleanup)
        .onChange(of: rtcManager?.isConnected) { _, connected in
            if let connected = connected, connected { activateCallIfNeeded() }
        }
        .onChange(of: rtcManager?.isEnded) { _, ended in
            if let ended = ended, ended { closeEndedCall() }
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if isVideo {
            ZStack {
                Color.black.ignoresSafeArea()
                if let remoteTrack = rtcManager?.remoteVideoTrack {
                    RTCVideoTrackView(videoTrack: remoteTrack, contentMode: .scaleAspectFill)
                        .ignoresSafeArea()
                } else if let localTrack = rtcManager?.localVideoTrack {
                    RTCVideoTrackView(videoTrack: localTrack, contentMode: .scaleAspectFill)
                        .ignoresSafeArea()
                        .opacity(0.75)
                } else {
                    videoPlaceholder
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.clear, Color.black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#0A0E27"), Color(hex: "#1A1040"), Color(hex: "#0D1B2A")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.primary.opacity(0.08 - Double(i) * 0.02), lineWidth: 1.5)
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
            }
        }
    }

    private var videoPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.35))
            Text("Attendo video remoto...")
                .foregroundColor(.white.opacity(0.55))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentLayer: some View {
        VStack(spacing: 0) {
            headerBar
            Spacer()
            callerInfo
            Spacer()
            bottomControls
        }
        .overlay(alignment: .topTrailing) {
            if isVideo, let localTrack = rtcManager?.localVideoTrack, rtcManager?.remoteVideoTrack != nil {
                RTCVideoTrackView(videoTrack: localTrack, contentMode: .scaleAspectFill)
                    .frame(width: 116, height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                    .padding(.top, 74)
                    .padding(.trailing, 18)
                    .opacity(isCameraEnabled ? 1 : 0.35)
            }
        }
    }

    private var headerBar: some View {
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
                Text(isVideo ? "Videochiamata WebRTC" : "Chiamata WebRTC")
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

            Button(action: toggleSpeaker) {
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
    }

    private var callerInfo: some View {
        VStack(spacing: 16) {
            ZStack {
                if callState == .connecting {
                    Circle()
                        .stroke(Theme.primary.opacity(0.3), lineWidth: 3)
                        .frame(width: pulseAnimation ? 140 : 120, height: pulseAnimation ? 140 : 120)
                    Circle()
                        .stroke(Theme.primary.opacity(0.15), lineWidth: 2)
                        .frame(width: pulseAnimation ? 170 : 145, height: pulseAnimation ? 170 : 145)
                }

                Circle()
                    .fill(LinearGradient(
                        colors: [Theme.primary, Theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 110, height: 110)
                    .shadow(color: Theme.primary.opacity(0.4), radius: 20, x: 0, y: 8)
                    .overlay(
                        Text(String(friend.username.prefix(1)).uppercased())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5))
                    .opacity(isVideo && rtcManager?.remoteVideoTrack != nil ? 0.0 : 1.0)
            }

            Text(friend.username)
                .font(.title.bold())
                .foregroundColor(.white)

            VStack(spacing: 6) {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(rtcManager?.errorMessage ?? rtcManager?.connectionStateText ?? "Initializing...")
                    .font(.caption)
                    .foregroundColor(
                        rtcManager?.errorMessage == nil
                            ? .white.opacity(0.55)
                            : .red.opacity(0.9)
                    )
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 20) {
            if isVideo { videoControls } else { audioControls }

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
        .padding(.bottom, 34)
    }

    // MARK: - Controls

    private var audioControls: some View {
        HStack(spacing: 20) {
            callControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                label: isMuted ? "Attiva" : "Muto",
                isActive: isMuted,
                activeColor: .orange
            ) { toggleMute() }

            callControlButton(
                icon: "person.badge.plus.fill",
                label: "Invita",
                isActive: false,
                activeColor: Theme.primary
            ) { showInviteSheet = true }

            callControlButton(
                icon: "video.fill",
                label: "Video",
                isActive: false,
                activeColor: Theme.primary
            ) {}
            .disabled(true)
            .opacity(0.45)
        }
    }

    private var videoControls: some View {
        HStack(spacing: 16) {
            callControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                label: isMuted ? "Attiva" : "Muto",
                isActive: isMuted,
                activeColor: .orange
            ) { toggleMute() }

            callControlButton(
                icon: isCameraEnabled ? "video.fill" : "video.slash.fill",
                label: isCameraEnabled ? "Camera" : "Camera off",
                isActive: !isCameraEnabled,
                activeColor: .orange
            ) { toggleCamera() }

            callControlButton(
                icon: "camera.rotate.fill",
                label: "Ruota",
                isActive: false,
                activeColor: Theme.primary
            ) { rtcManager?.switchCamera() }
            .disabled(!isCameraEnabled)
            .opacity(isCameraEnabled ? 1 : 0.4)

            callControlButton(
                icon: "person.badge.plus.fill",
                label: "Invita",
                isActive: false,
                activeColor: Theme.primary
            ) { showInviteSheet = true }
        }
    }

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
                    .background(isActive ? activeColor.opacity(0.2) : Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
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

    // MARK: - State helpers

    private var statusText: String {
        switch callState {
        case .connecting: return isCaller ? "Chiamata in corso..." : "Connessione in corso..."
        case .active:     return isVideo ? "Videochiamata attiva" : "In chiamata"
        case .ended:      return "Chiamata terminata"
        }
    }

    private var statusColor: Color {
        switch callState {
        case .connecting: return .orange
        case .active:     return Theme.online
        case .ended:      return .red
        }
    }

    private var timeString: String {
        let m = callDuration / 60
        let s = callDuration % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Lifecycle

    private func startCallLifecycle() {
        setupAudio()
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }

        guard !didStartRTC else { return }
        didStartRTC = true

        guard let signalID = signalID,
              let userID = authVM.currentUser?.id else {
            errorMessage = "❌ Missing signalID or userID"
            return
        }

        // Initialize rtcManager
        rtcManager = WebRTCCallManager()

        Task { @MainActor [weak self] in
            guard let self = self, let manager = self.rtcManager else { return }
            
            await manager.start(
                signalID: signalID,
                currentUserID: userID,
                isCaller: self.isCaller,
                isVideo: self.isVideo
            )
        }

        callSignalListener = dataService.subscribeCallStatus(signalID: signalID) { status in
            if status == "accepted" { activateCallIfNeeded() }
            if status == "declined" || status == "ended" { closeEndedCall() }
        }
    }

    private func activateCallIfNeeded() {
        guard callState != .active else { return }
        withAnimation(.spring(response: 0.5)) {
            callState = .active
        }
        startTimer()
    }

    private func closeEndedCall() {
        callState = .ended
        timer?.invalidate()
        rtcManager?.end()
        callSignalListener?.remove()
        callSignalListener = nil
        dismiss()
    }

    private func hangUp() {
        callState = .ended
        rtcManager?.end()
        if let sid = signalID {
            Task { try? await dataService.endCall(signalID: sid) }
        }
        callSignalListener?.remove()
        dismiss()
    }

    private func cleanup() {
        timer?.invalidate()
        callSignalListener?.remove()
        callSignalListener = nil
        rtcManager?.end()
        try? audioSession.setActive(false)
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            callDuration += 1
        }
    }

    // MARK: - Audio / Video

    private func setupAudio() {
        try? audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothA2DP, .defaultToSpeaker]
        )
        try? audioSession.setActive(true)
    }

    private func toggleSpeaker() {
        isSpeakerOn.toggle()
        try? audioSession.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
    }

    private func toggleMute() {
        isMuted.toggle()
        rtcManager?.setMuted(isMuted)
    }

    private func toggleCamera() {
        guard isVideo else { return }
        isCameraEnabled.toggle()
        rtcManager?.setCameraEnabled(isCameraEnabled)
    }
    
    private var errorMessage: String {
        get { rtcManager?.errorMessage ?? "" }
        set {}
    }

    // MARK: - Invite Sheet

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
                                            .foregroundColor(
                                                candidate.isOnline ? Theme.online : Theme.textSecondary
                                            )
                                    }
                                    Spacer()
                                    Button {
                                        if let id = candidate.id { invitedFriendIDs.insert(id) }
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
