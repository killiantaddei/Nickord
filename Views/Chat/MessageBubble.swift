//
//  MessageBubble.swift
//  Nickord
//

import SwiftUI
import AVFoundation

// MARK: - Bubble principale

struct MessageBubble: View {
    let message: Message
    let isFromMe: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromMe { Spacer(minLength: 50) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {

                // Nome mittente (solo messaggi altrui)
                if !isFromMe {
                    Text(message.senderUsername)
                        .font(.caption)
                        .foregroundColor(Theme.primaryLight)
                        .padding(.leading, 6)
                }

                // Contenuto
                bubbleContent
                    .background(isFromMe ? Theme.bubbleMine : Theme.bubbleOther)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                // Orario
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(isFromMe ? .trailing : .leading, 6)
            }

            if !isFromMe { Spacer(minLength: 50) }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.type {
        case .text:
            Text(message.content)
                .foregroundColor(.white)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)

        case .audio:
            AudioBubble(audioURL: message.audioURL)

        case .image:
            if let urlString = message.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 200)
                            .clipped()
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        ProgressView()
                            .frame(width: 220, height: 140)
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
        }
    }

    private var imagePlaceholder: some View {
        Label("Immagine", systemImage: "photo")
            .font(.caption.italic())
            .foregroundColor(.white.opacity(0.7))
            .padding()
    }
}

// MARK: - Audio bubble

struct AudioBubble: View {
    let audioURL: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 12) {
            Button { togglePlayback() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
            }
            .disabled(audioURL == nil)

            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                        Capsule()
                            .fill(Color.white)
                            .frame(
                                width: duration > 0
                                    ? geo.size.width * CGFloat(currentTime / duration)
                                    : 0,
                                height: 4
                            )
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption2).foregroundColor(.white.opacity(0.75)).monospacedDigit()
                    Spacer()
                    Text(formatTime(duration))
                        .font(.caption2).foregroundColor(.white.opacity(0.5)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 200)
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: teardownPlayer)
    }

    private func setupPlayer() {
        guard let urlString = audioURL, let url = URL(string: urlString) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        Task {
            if let dur = try? await item.asset.load(.duration), !dur.seconds.isNaN {
                await MainActor.run { duration = dur.seconds }
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if currentTime >= duration && duration > 0 {
                isPlaying = false
                p.seek(to: .zero)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in isPlaying = false; currentTime = 0; p.seek(to: .zero) }
    }

    private func teardownPlayer() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        if isPlaying {
            player.pause(); isPlaying = false
        } else {
            if currentTime >= duration && duration > 0 { player.seek(to: .zero) }
            player.play(); isPlaying = true
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard !s.isNaN, !s.isInfinite else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - RoundedCorner helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
