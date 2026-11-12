import AVFoundation
import AVKit
import DLData
import DLDesignSystem
import DLNetwork
import Observation
import SwiftUI
import UIKit

/// One voice note playing at a time across the app (web media/onePlayer.ts).
@MainActor
@Observable
public final class OnePlayer: NSObject, AVAudioPlayerDelegate {
    public static let shared = OnePlayer()

    public private(set) var playing: String?
    public private(set) var loading: String?
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var files: [String: URL] = [:]

    public func toggle(_ url: String, client: APIClient) {
        if playing == url {
            pause()
            return
        }
        Task { await play(url, client: client) }
    }

    public func pause() {
        player?.pause()
        playing = nil
        ticker?.cancel()
    }

    public func seek(_ url: String, to fraction: Double) {
        guard playing == url, let player else { return }
        player.currentTime = player.duration * fraction
        position = player.currentTime
    }

    private func play(_ url: String, client: APIClient) async {
        player?.stop()
        ticker?.cancel()
        playing = nil
        loading = url
        defer { if loading == url { loading = nil } }
        let file: URL
        if let cached = files[url] {
            file = cached
        } else {
            guard let data = try? await client.data(for: client.makeRequest("GET", url)) else { return }
            let target = FileManager.default.temporaryDirectory.appending(path: "voice-\(abs(url.hashValue)).m4a")
            try? data.write(to: target)
            files[url] = target
            file = target
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: file) else { return }
        p.delegate = self
        player = p
        duration = p.duration
        position = 0
        p.play()
        playing = url
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
            }
        }
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = nil
            self.position = 0
            self.ticker?.cancel()
        }
    }
}

/// A voice note on paper (web .dl-voice): a round play button, the track with its progress, the
/// time. One plays at a time.
public struct VoicePlayer: View {
    let url: String
    let durationMs: Int?
    let label: String

    @Environment(Backend.self) private var backend
    private var player: OnePlayer { OnePlayer.shared }

    public init(url: String, durationMs: Int?, label: String = "voice note") {
        self.url = url
        self.durationMs = durationMs
        self.label = label
    }

    public var body: some View {
        let isPlaying = player.playing == url
        let total = isPlaying && player.duration > 0 ? player.duration : Double(durationMs ?? 0) / 1000
        let fraction = isPlaying && total > 0 ? player.position / total : 0
        HStack(spacing: 12) {
            Button { player.toggle(url, client: backend.client) } label: {
                ZStack {
                    Circle().fill(.dlSeal)
                    if player.loading == url {
                        ProgressView().tint(.dlOnSeal).controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.dlOnSeal)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(DLPressStyle())
            .accessibilityLabel(isPlaying ? "Pause \(label)" : "Play \(label)")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dlLetterInk.opacity(0.15)).frame(height: 4)
                    Capsule().fill(.dlSeal).frame(width: geo.size.width * fraction, height: 4)
                    Circle().fill(.dlSeal).frame(width: 12, height: 12).offset(x: geo.size.width * fraction - 6)
                        .opacity(isPlaying ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    player.seek(url, to: min(1, max(0, v.location.x / max(1, geo.size.width))))
                })
            }
            .frame(height: 24)
            .accessibilityHidden(true)
            Text(DLTime.mediaLength(ms: Int((isPlaying ? player.position : total) * 1000)))
                .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 13, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(.dlLetterInk)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .background(Color.dlLetterInk.opacity(0.05), in: Capsule())
    }
}

/// Photos full screen (canvas C-Lightbox): swipe between them, pinch or double-tap to zoom,
/// "2 of 3", Close. A doodle opens the same way, titled.
public struct Lightbox: View {
    let items: [Att]
    @State private var index: Int
    let title: String?
    let onClose: () -> Void

    public init(items: [Att], index: Int, title: String? = nil, onClose: @escaping () -> Void) {
        self.items = items
        _index = State(initialValue: index)
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Color.dlLightbox.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    ZoomableImage(url: item.url).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.dlOnLightbox)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text(title ?? (items.count > 1 ? "\(index + 1) of \(items.count)" : ""))
                        .dlText(.subheadline)
                        .foregroundStyle(.dlOnLightbox)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
        .statusBarHidden()
    }
}

private struct ZoomableImage: View {
    let url: String
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        RemoteImage(url, contentMode: .fit, maxPixel: 2400) { ProgressView().tint(.dlOnLightbox) }
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = max(1, min(4, base * v.magnification)) }
                    .onEnded { _ in base = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(DLMotion.easeOut(0.25)) {
                    scale = scale > 1 ? 1 : 2.5
                    base = scale
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A video full screen (emails): downloaded with the session cookie, then played by the system player.
public struct VideoPlayerScreen: View {
    let path: String
    let onClose: () -> Void
    @Environment(Backend.self) private var backend
    @State private var player: AVPlayer?
    @State private var failed = false

    public init(path: String, onClose: @escaping () -> Void) {
        self.path = path
        self.onClose = onClose
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea().onAppear { player.play() }
            } else if failed {
                Text("Couldn’t load the video. Try again.").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .task {
            guard let data = try? await backend.client.data(for: backend.client.makeRequest("GET", path), timeout: 120) else {
                failed = true
                return
            }
            let file = FileManager.default.temporaryDirectory.appending(path: "play-\(abs(path.hashValue)).mp4")
            try? data.write(to: file)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = AVPlayer(url: file)
        }
    }
}
