import AVFoundation
import DLData
import DLDesignSystem
import DLNetwork
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Voice notes (web media/VoiceRecorder): AAC in .m4a, stop at five minutes. The system asks for
/// the microphone once; a refusal shows a toast with Settings.
@MainActor
@Observable
public final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    public static let maxSeconds: TimeInterval = 5 * 60

    public private(set) var recording = false
    public private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private let onDone: (Data, Int) -> Void

    public init(onDone: @escaping (Data, Int) -> Void) {
        self.onDone = onDone
    }

    /// False when the microphone is refused.
    public func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.delegate = self
        r.record(forDuration: Self.maxSeconds)
        recorder = r
        file = url
        recording = true
        elapsed = 0
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let r = self.recorder else { return }
                self.elapsed = r.currentTime
            }
        }
        return true
    }

    public func stop() {
        guard recording, let r = recorder else { return }
        let length = r.currentTime
        r.stop()
        finish(length: length)
    }

    private func finish(length: TimeInterval) {
        ticker?.cancel()
        recording = false
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let file, let data = try? Data(contentsOf: file), length > 0.3 else { return }
        onDone(data, Int(length * 1000))
    }

    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if self.recording { self.finish(length: Self.maxSeconds) }
        }
    }
}

/// The add row under the writing (canvas W-Draft): photos, a voice note (tap to record, tap to
/// stop), an audio file, and a doodle (one per letter).
public struct AddBar: View {
    let attachments: Attachments
    let recorder: VoiceRecorder
    let enabled: Bool
    let doodleFull: Bool
    let onDoodle: () -> Void

    @Environment(\.dlNotice) private var notice
    @Environment(\.dlBrand) private var brand
    @Environment(\.openURL) private var openURL
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false

    public init(attachments: Attachments, recorder: VoiceRecorder, enabled: Bool, doodleFull: Bool, onDoodle: @escaping () -> Void) {
        self.attachments = attachments
        self.recorder = recorder
        self.enabled = enabled
        self.doodleFull = doodleFull
        self.onDoodle = onDoodle
    }

    public var body: some View {
        let on = enabled
        HStack(spacing: 4) {
            PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) {
                AddIcon(symbol: "photo.on.rectangle", enabled: on)
            }
            .disabled(!enabled)
            .accessibilityLabel("Add photo")
            if recorder.recording {
                Button { recorder.stop() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(.dlError).frame(width: 10, height: 10)
                        Text(DLTime.mediaLength(ms: Int(recorder.elapsed * 1000))).monospacedDigit()
                        Image(systemName: "stop.fill")
                    }
                    .font(.custom(DLFontName.manropeBold.rawValue, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(.dlError)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(.dlErrorTint, in: Capsule())
                }
                .accessibilityLabel("Stop recording")
            } else {
                Button {
                    Task {
                        if await !recorder.start() {
                            notice(DLToastItem("Microphone is off for \(brand)", actionTitle: "Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            })
                        }
                    }
                } label: { icon("mic") }
                    .disabled(!enabled)
                    .accessibilityLabel("Record a voice note")
            }
            Button { importing = true } label: { icon("waveform.badge.plus") }
                .disabled(!enabled || recorder.recording)
                .accessibilityLabel("Attach audio file")
            Button(action: onDoodle) { icon("scribble") }
                .disabled(!enabled || doodleFull || recorder.recording)
                .accessibilityLabel(doodleFull ? "Doodle attached · one per letter" : "Draw a doodle")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .onChange(of: photos) { _, picked in
            for item in picked {
                attachments.add(.photo, name: "photo.jpg", mime: "image/jpeg") {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw Attachments.ReadError() }
                    return data
                }
            }
            photos = []
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let name = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "audio/mp4"
            attachments.add(.audio, name: name, mime: mime) {
                let open = url.startAccessingSecurityScopedResource()
                defer { if open { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { throw Attachments.ReadError() }
                return data
            }
        }
    }

    private func icon(_ symbol: String) -> some View {
        AddIcon(symbol: symbol, enabled: enabled)
    }
}

private struct AddIcon: View {
    let symbol: String
    let enabled: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(enabled ? Color.dlInk : Color.dlInkDisabled)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
