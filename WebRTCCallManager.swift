import Foundation
@preconcurrency import AVFoundation
import WebRTC
import Combine

@MainActor
final class WebRTCCallManager: NSObject, ObservableObject {
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var remoteAudioTrack: RTCAudioTrack?
    @Published var connectionStateText: String = "Preparazione RTC..."
    @Published var errorMessage: String?
    @Published var isConnected = false
    @Published var isEnded = false

    private static var didInitializeWebRTC = false

    private let dataService = DataService.shared
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoSource: RTCVideoSource?
    private var cameraCapturer: RTCCameraVideoCapturer?
    private var signalingTask: Task<Void, Never>?
    private var signalID: String?
    private var currentUserID: String?
    private var isCaller = false
    private var isVideo = false
    
    // WebRTC state tracking
    private var hasCreatedLocalOffer = false
    private var hasCreatedLocalAnswer = false
    private var hasAppliedRemoteOffer = false
    private var hasAppliedRemoteAnswer = false
    private var receivedCandidateIDs = Set<String>()
    private var sentCandidates = Set<String>()

    override init() {
        super.init()
    }

    func start(signalID: String, currentUserID: String, isCaller: Bool, isVideo: Bool) async {
        guard self.signalID == nil else { return }
        self.signalID = signalID
        self.currentUserID = currentUserID
        self.isCaller = isCaller
        self.isVideo = isVideo

        configureAudioSession()
        configurePeerConnection()
        addLocalAudio()
        
        if isVideo {
            addLocalVideo()
        }

        if isCaller {
            await createAndPublishOffer()
        }
        
        startSignalingLoop()
    }

    func end() {
        guard !isEnded else { return }
        
        print("🔧 WebRTCCallManager.end() called")
        
        signalingTask?.cancel()
        signalingTask = nil
        
        // Clean up camera
        if let capturer = cameraCapturer {
            capturer.stopCapture { [weak self] in
                DispatchQueue.main.async {
                    self?.cameraCapturer = nil
                }
            }
        }
        
        // Clean up tracks
        localAudioTrack = nil
        localVideoTrack = nil
        remoteAudioTrack = nil
        remoteVideoTrack = nil
        
        // Clean up peer connection
        peerConnection?.close()
        peerConnection = nil
        
        // Clean up factory
        peerConnectionFactory = nil
        
        // Update state
        isConnected = false
        isEnded = true
        connectionStateText = "Chiamata terminata"
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("❌ Audio session deactivation failed: \(error)")
        }
    }
    
    deinit {
        print("🔧 WebRTCCallManager deinit")
        Task { @MainActor [weak self] in
            self?.end()
        }
    }

    func setMuted(_ muted: Bool) {
        localAudioTrack?.isEnabled = !muted
    }

    func setCameraEnabled(_ enabled: Bool) {
        localVideoTrack?.isEnabled = enabled
    }

    func switchCamera() {
        guard let capturer = cameraCapturer,
              !isEnded,
              let current = capturer.captureSession.inputs.first as? AVCaptureDeviceInput else { 
            print("🔧 Cannot switch camera - no capturer or input")
            return 
        }
        
        let nextPosition: AVCaptureDevice.Position = current.device.position == .front ? .back : .front
        guard let device = Self.captureDevice(position: nextPosition),
              let format = Self.bestFormat(for: device),
              let fps = Self.bestFPS(for: format) else { 
            print("🔧 Cannot switch camera - no device or format")
            return 
        }
        
        capturer.stopCapture { [weak self] in
            Task { @MainActor [weak self] in
                self?.cameraCapturer?.startCapture(with: device, format: format, fps: fps)
            }
        }
    }

    // MARK: - Private Setup

    private func configurePeerConnection() {
        guard !isEnded else { return }
        
        if !Self.didInitializeWebRTC {
            RTCInitializeSSL()
            Self.didInitializeWebRTC = true
        }

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        guard let factory = peerConnectionFactory else {
            errorMessage = "Failed to create peer connection factory"
            return
        }

        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
        connectionStateText = "Connessione WebRTC creata"
    }

    private func addLocalAudio() {
        guard !isEnded, let factory = peerConnectionFactory else {
            errorMessage = "Cannot add audio - factory not available"
            return
        }
        
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        
        guard audioTrack != nil else {
            errorMessage = "Failed to create audio track"
            return
        }
        
        localAudioTrack = audioTrack
        peerConnection?.add(audioTrack, streamIds: ["nickord-stream"])
        print("✅ Audio track added")
    }

    private func addLocalVideo() {
        guard !isEnded, let factory = peerConnectionFactory else {
            errorMessage = "Cannot add video - factory not available"
            return
        }
        
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        
        guard videoTrack != nil else {
            errorMessage = "Failed to create video track"
            return
        }
        
        localVideoSource = videoSource
        localVideoTrack = videoTrack
        peerConnection?.add(videoTrack, streamIds: ["nickord-stream"])
        print("✅ Video track added")
        
        startCameraCapture(videoSource: videoSource)
    }

    private func startCameraCapture(videoSource: RTCVideoSource) {
        guard cameraCapturer == nil else {
            print("Camera capture already started")
            return
        }
        
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        cameraCapturer = capturer
        
        guard
            let device = Self.captureDevice(position: .front),
            let format = Self.bestFormat(for: device),
            let fps = Self.bestFPS(for: format)
        else {
            errorMessage = "Camera non disponibile"
            return
        }
        
        do {
            try capturer.startCapture(with: device, format: format, fps: fps)
            print("✅ Camera capture started")
        } catch {
            errorMessage = "Errore avvio camera: \(error.localizedDescription)"
            cameraCapturer = nil
        }
    }

    private static func captureDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        RTCCameraVideoCapturer.captureDevices().first { $0.position == position }
            ?? RTCCameraVideoCapturer.captureDevices().first
    }

    private static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard !formats.isEmpty else { return nil }
        
        return formats.sorted { lhs, rhs in
            let lhsSize = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsSize = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return lhsSize.width * lhsSize.height > rhsSize.width * rhsSize.height
        }.first
    }

    private static func bestFPS(for format: AVCaptureDevice.Format) -> Int? {
        let frameRateRanges = format.videoSupportedFrameRateRanges
        guard !frameRateRanges.isEmpty else { return 30 }
        
        let maxFPS = frameRateRanges
            .map { Int($0.maxFrameRate) }
            .max() ?? 30
        return min(maxFPS, 30)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Audio session configuration failed: \(error)")
        }
    }

    // MARK: - Signaling: Offer / Answer

    private func createAndPublishOffer() async {
        guard let peerConnection, let signalID else { return }
        guard !hasCreatedLocalOffer else { return }
        hasCreatedLocalOffer = true
        
        print("🔧 Creating offer...")
        
        do {
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "true",
                    "OfferToReceiveVideo": isVideo ? "true" : "false"
                ],
                optionalConstraints: nil
            )
            let offer = try await peerConnection.offer(for: constraints)
            try await peerConnection.setLocalDescription(offer)
            try await dataService.saveOffer(signalID: signalID, sdp: offer.sdp, type: "offer")
            connectionStateText = "Invito inviato, in attesa di risposta..."
            print("✅ Offer created and published")
        } catch {
            errorMessage = error.localizedDescription
            connectionStateText = "Errore creazione offer"
            print("❌ Offer error: \(error)")
        }
    }

    private func createAndPublishAnswer(from offerRecord: SBCallSignalRecord) async {
        guard let peerConnection, let signalID else { return }
        guard !hasCreatedLocalAnswer else { return }
        guard let offerSDP = offerRecord.offer_sdp, !offerSDP.isEmpty else { return }
        
        print("🔧 Creating answer...")
        hasCreatedLocalAnswer = true
        
        do {
            let offer = RTCSessionDescription(type: .offer, sdp: offerSDP)
            try await peerConnection.setRemoteDescription(offer)
            hasAppliedRemoteOffer = true
            
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "true",
                    "OfferToReceiveVideo": isVideo ? "true" : "false"
                ],
                optionalConstraints: nil
            )
            let answer = try await peerConnection.answer(for: constraints)
            try await peerConnection.setLocalDescription(answer)
            try await dataService.saveAnswer(signalID: signalID, sdp: answer.sdp, type: "answer")
            connectionStateText = "Risposta inviata, connessione in corso..."
            print("✅ Answer created and published")
        } catch {
            errorMessage = error.localizedDescription
            connectionStateText = "Errore creazione answer"
            print("❌ Answer error: \(error)")
        }
    }

    private func applyRemoteAnswerIfNeeded(_ record: SBCallSignalRecord) async {
        guard isCaller, !hasAppliedRemoteAnswer, let peerConnection else { return }
        guard let answerSDP = record.answer_sdp, !answerSDP.isEmpty else { return }
        
        print("🔧 Applying remote answer...")
        
        do {
            let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
            try await peerConnection.setRemoteDescription(answer)
            hasAppliedRemoteAnswer = true
            connectionStateText = "Risposta ricevuta, connessione in corso..."
            print("✅ Remote answer applied")
        } catch {
            errorMessage = error.localizedDescription
            connectionStateText = "Errore applicazione answer"
            print("❌ Apply answer error: \(error)")
        }
    }

    // MARK: - Signaling Loop

    private func startSignalingLoop() {
        signalingTask?.cancel()
        signalingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.pollSignaling()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        print("🔧 Signaling loop started")
    }

    private func pollSignaling() async {
        guard let signalID, let currentUserID, !signalID.isEmpty, !currentUserID.isEmpty else { return }
        
        do {
            if let record = try await dataService.fetchCallSignal(signalID: signalID) {
                if record.status == "ended" || record.status == "declined" {
                    await MainActor.run {
                        end()
                    }
                    return
                }
                
                // Callee: wait for offer then create answer
                if !isCaller, !hasCreatedLocalAnswer {
                    await createAndPublishAnswer(from: record)
                }
                
                // Caller: apply remote answer
                if isCaller {
                    await applyRemoteAnswerIfNeeded(record)
                }
            }

            // Fetch and process ICE candidates
            let candidates = try await dataService.fetchIceCandidates(
                signalID: signalID,
                excludingSenderID: currentUserID
            )
            
            for item in candidates {
                guard
                    let id = item.id,
                    !receivedCandidateIDs.contains(id),
                    let candidateSDP = item.candidate,
                    !candidateSDP.isEmpty
                else { continue }

                await MainActor.run {
                    guard let peerConnection = self.peerConnection else { return }
                    
                    let candidate = RTCIceCandidate(
                        sdp: candidateSDP,
                        sdpMLineIndex: item.sdp_mline_index ?? 0,
                        sdpMid: (item.sdp_mid?.isEmpty ?? true) ? nil : item.sdp_mid
                    )
                    
                    Task {
                        do {
                            try await peerConnection.add(candidate)
                            await MainActor.run {
                                self.receivedCandidateIDs.insert(id)
                            }
                            print("✅ ICE candidate added: \(candidateSDP.prefix(40))...")
                        } catch {
                            print("❌ Failed to add ICE candidate: \(error)")
                        }
                    }
                }
            }
        } catch {
            print("❌ Signaling error: \(error)")
        }
    }

    private func publishCandidate(_ candidate: RTCIceCandidate) async {
        guard let signalID, let currentUserID else { return }
        let key = "\(candidate.sdpMid ?? "")-\(candidate.sdpMLineIndex)-\(candidate.sdp)"
        guard !sentCandidates.contains(key) else { return }
        sentCandidates.insert(key)
        do {
            try await dataService.addIceCandidate(
                signalID: signalID,
                senderID: currentUserID,
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            )
            print("✅ ICE candidate published")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to publish ICE candidate: \(error)")
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCCallManager: RTCPeerConnectionDelegate {

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        Task { @MainActor [weak self] in
            await self?.publishCandidate(candidate)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCPeerConnectionState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .connected:
                self.isConnected = true
                self.connectionStateText = "✅ Connesso"
                print("✅ Peer connected")
            case .connecting:
                self.connectionStateText = "🔧 Connessione peer in corso..."
            case .disconnected:
                self.isConnected = false
                self.connectionStateText = "⚠️ Peer disconnesso"
            case .failed:
                self.isConnected = false
                self.connectionStateText = "❌ Connessione WebRTC fallita"
            case .closed:
                self.isConnected = false
                self.connectionStateText = "Connessione chiusa"
            case .new:
                self.connectionStateText = "Peer creato"
            @unknown default:
                self.connectionStateText = "Stato WebRTC sconosciuto"
            }
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd receiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        if let videoTrack = receiver.track as? RTCVideoTrack {
            Task { @MainActor [weak self] in
                self?.remoteVideoTrack = videoTrack
                print("✅ Remote video track received")
            }
        } else if let audioTrack = receiver.track as? RTCAudioTrack {
            Task { @MainActor [weak self] in
                self?.remoteAudioTrack = audioTrack
                print("✅ Remote audio track received")
            }
        }
    }
}

// MARK: - RTCPeerConnection async extensions

extension RTCPeerConnection {

    func offer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            self.offer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: SBError.noData)
                }
            }
        }
    }

    func answer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            self.answer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: SBError.noData)
                }
            }
        }
    }

    func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setLocalDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setRemoteDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func add(_ candidate: RTCIceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
