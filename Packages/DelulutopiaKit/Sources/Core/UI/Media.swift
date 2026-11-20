import AVFoundation
import AVKit
import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import Observation
import SwiftUI
import UIKit
import os

/// One voice note playing at a time across the app (web media/onePlayer.ts).
///
/// A voice-note player's play also follows doc "Delululand — Earpiece Playback": a 0.5 s wait before
/// the start (EP6), the proximity sensor picks earpiece or loudspeaker (EP1) and turns the screen off at
/// the ear (EP4), taking the phone off the ear pauses (EP2), and the run's next notes follow after
/// 0.5 s each (EP7–EP9).
@MainActor
@Observable
public final class OnePlayer: NSObject, AVAudioPlayerDelegate {
    public static let shared = OnePlayer()

    /// EP6/EP9: the wait before a voice note starts, and between the notes of a run. Config-only.
    public static let voiceDelay: Duration = .milliseconds(500)

    public private(set) var playing: String?
    public private(set) var loading: String?
    /// EP6: the note waiting out its 0.5 s before it starts.
    public private(set) var pending: String?
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// Voice Note Speed VS4: the pick kept on this phone, shared by every note.
    public private(set) var speed: Float = VoiceSpeed.stored()

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var files: [String: URL] = [:]
    @ObservationIgnored private var wait: Task<Void, Never>?
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var proximityObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var onEar = false

    /// True while an earpiece session (proximity monitoring) runs.
    public var earpieceSession: Bool { proximityObserver != nil }

    /// A voice-note player's play/pause. `next` are the run's notes after `url` (EP7).
    public func toggle(_ url: String, next: [String] = [], client: APIClient) {
        if playing == url || pending == url {
            pause()
            return
        }
        self.client = client
        cancelRun()
        queue = next
        if playing != nil { player?.pause(); playing = nil; ticker?.cancel() }
        guard Earpiece.usable() else {
            endSession()
            Task { await play(url, client: client) }
            return
        }
        // EP13 (revised 20 Nov): the receiver route is a record-capable session, so a phone that was
        // never asked for the mic asks once, here, while the phone is still in hand. Denied still
        // works: the route plays, the unused input just records silence.
        if AVAudioApplication.shared.recordPermission == .undetermined {
            pending = url
            wait = Task { [weak self] in
                let granted = await AVAudioApplication.requestRecordPermission()
                Earpiece.log.info("mic asked: granted=\(granted)")
                guard !Task.isCancelled, let self else { return }
                self.startSession()
                self.later(url)
            }
            return
        }
        startSession()
        later(url)
    }

    /// Pauses and ends the run and any earpiece session; the next play waits 0.5 s again (EP2).
    public func pause() {
        cancelRun()
        player?.pause()
        playing = nil
        ticker?.cancel()
        endSession()
    }

    /// VS5: applies at once, from the current position; AVAudioPlayer's rate keeps the pitch (VS6).
    public func setSpeed(_ s: Float) {
        speed = s
        VoiceSpeed.store(s)
        player?.rate = s
    }

    public func seek(_ url: String, to fraction: Double) {
        guard playing == url, let player else { return }
        player.currentTime = player.duration * fraction
        position = player.currentTime
    }

    private func later(_ url: String) {
        pending = url
        wait = Task { [weak self] in
            try? await Task.sleep(for: Self.voiceDelay)
            guard !Task.isCancelled, let self, let client = self.client else { return }
            self.pending = nil
            await self.play(url, client: client)
        }
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
        // EP1: the route at the start is the sensor's word; without a session, the loudspeaker.
        route(ear: earpieceSession && UIDevice.current.proximityState, force: true)
        guard let p = try? AVAudioPlayer(contentsOf: file) else { return }
        p.delegate = self
        p.enableRate = true
        p.prepareToPlay()
        p.rate = speed
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

    /// EP7–EP9: the next note of the run after 0.5 s, on the same session; else the session ends.
    private func ended() {
        playing = nil
        position = 0
        ticker?.cancel()
        guard !queue.isEmpty else {
            endSession()
            return
        }
        later(queue.removeFirst())
    }

    /// EP1: raised mid-note → earpiece in place; EP2: taken off the ear → pause.
    private func proximityChanged() {
        let near = UIDevice.current.proximityState
        Earpiece.log.info("proximity near=\(near) onEar=\(self.onEar) playing=\(self.playing != nil) pending=\(self.pending != nil)")
        if near, !onEar, playing != nil || pending != nil {
            route(ear: true)
        } else if !near, onEar {
            pause()
        }
    }

    /// Earpiece = `.playAndRecord` (the receiver is its default output; needs the mic grant, EP13);
    /// loudspeaker = the app's usual `.playback` / spoken audio.
    private func route(ear: Bool, force: Bool = false) {
        guard force || ear != onEar else { return }
        onEar = ear
        let session = AVAudioSession.sharedInstance()
        do {
            if ear {
                try session.setCategory(.playAndRecord, mode: .default, options: [])
                try session.overrideOutputAudioPort(.none)
            } else {
                try session.setCategory(.playback, mode: .spokenAudio)
            }
            try session.setActive(true)
        } catch {
            Earpiece.log.error("route ear=\(ear) failed: \(error.localizedDescription)")
        }
        Earpiece.log.info("route ear=\(ear) outputs=\(session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ","))")
    }

    /// EP4: proximity monitoring turns the screen off at the ear (no touches) and reports near/far.
    private func startSession() {
        guard proximityObserver == nil else { return }
        UIDevice.current.isProximityMonitoringEnabled = true
        Earpiece.log.info("session start, monitoring=\(UIDevice.current.isProximityMonitoringEnabled)")
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in OnePlayer.shared.proximityChanged() }
        }
    }

    private func endSession() {
        if onEar { route(ear: false) }
        guard let observer = proximityObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        proximityObserver = nil
        UIDevice.current.isProximityMonitoringEnabled = false
    }

    private func cancelRun() {
        wait?.cancel()
        wait = nil
        pending = nil
        queue = []
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.ended() }
    }
}

/// Raise-to-listen availability (EP3, EP11).
@MainActor
enum Earpiece {
    /// Console: subsystem com.delulutopia.app, category earpiece.
    nonisolated static let log = Logger(subsystem: "com.delulutopia.app", category: "earpiece")

    /// An iPhone (every iPhone has the earpiece and the proximity sensor) with no headset connected
    /// (the headset wins, EP3).
    static func usable() -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            log.info("off: not a phone")
            return false
        }
        let headsets: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .airPlay, .carAudio]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if let h = outputs.first(where: { headsets.contains($0.portType) }) {
            log.info("off: headset \(h.portType.rawValue)")
            return false
        }
        return true
    }
}

/// A voice note on paper (web .dl-voice): a round play button, the track with its progress, the
/// time. One plays at a time.
public struct VoicePlayer: View {
    let url: String
    let durationMs: Int?
    let label: String
    /// EP7: the run's notes that play on after this one.
    let next: [String]

    @Environment(Backend.self) private var backend
    @Environment(\.scenePhase) private var scenePhase
    private var player: OnePlayer { OnePlayer.shared }

    public init(url: String, durationMs: Int?, label: String = t("media.voiceNoteLower"), next: [String] = []) {
        self.url = url
        self.durationMs = durationMs
        self.label = label
        self.next = next
    }

    public var body: some View {
        // EP6: during the 0.5 s wait the button already shows pause; a tap cancels the start.
        let isPlaying = player.playing == url || player.pending == url
        let active = player.playing == url
        let total = active && player.duration > 0 ? player.duration : Double(durationMs ?? 0) / 1000
        let fraction = active && total > 0 ? player.position / total : 0
        HStack(spacing: 12) {
            Button { player.toggle(url, next: next, client: backend.client) } label: {
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
            .accessibilityLabel(isPlaying ? t("media.pause", ["label": label]) : t("media.play", ["label": label]))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dlLetterInk.opacity(0.15)).frame(height: 4)
                    Capsule().fill(.dlSeal).frame(width: geo.size.width * fraction, height: 4)
                    Circle().fill(.dlSeal).frame(width: 12, height: 12).offset(x: geo.size.width * fraction - 6)
                        .opacity(active ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    player.seek(url, to: min(1, max(0, v.location.x / max(1, geo.size.width))))
                })
            }
            .frame(height: 24)
            .accessibilityHidden(true)
            Text(DLTime.mediaLength(ms: Int((active ? player.position : total) * 1000)))
                .font(.custom(DLFontName.manropeSemiBold.name, size: 13, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(.dlLetterInk)
            // VS3/VS8: the speed chip, always shown; a tap moves every note to the next speed.
            let speedLabel = VoiceSpeed.label(player.speed)
            Button { player.setSpeed(VoiceSpeed.next(player.speed)) } label: {
                Text(speedLabel)
                    .font(.custom(DLFontName.manropeBold.name, size: 12, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(.dlLetterInk)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 36, minHeight: 24)
                    .overlay(Capsule().strokeBorder(Color.dlLetterInk.opacity(0.2), lineWidth: 1))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DLPressStyle())
            .accessibilityLabel(t("media.playbackSpeed", ["speed": speedLabel]))
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.dlLetterInk.opacity(0.05), in: Capsule())
        // L5: a player's track runs left to right in every language, like the phone's own players.
        .environment(\.layoutDirection, .leftToRight)
        // The earpiece session (sensor, screen-off, call route) never outlives the screen.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, player.earpieceSession, player.playing == url || player.pending == url { player.pause() }
        }
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
                    .accessibilityLabel(t("media.close"))
                    Spacer()
                    Text(title ?? (items.count > 1 ? t("media.nOf", ["n": index + 1, "count": items.count]) : ""))
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
                Text(t("media.videoNotLoaded")).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
            }
            .padding(16)
            .accessibilityLabel(t("media.close"))
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
