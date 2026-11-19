import AVFoundation
import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Emails Q4, Q5: plain text, counted in grapheme clusters, at most 1024.
let emailMax = 1024
let subjectMax = 120
var trimmedLine: String { t("emails.trimmed") }

func normalize(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }

/// The first `max` characters; `cut` says whether anything was dropped.
func clamp(_ text: String, max: Int = emailMax) -> (String, Bool) {
    let n = normalize(text)
    return n.count <= max ? (n, false) : (String(n.prefix(max)), true)
}

/// Q20, Q21: "N left today · renews at HH:MM", or the out-of-credits line.
func creditsLine(_ c: EmailCredits?) -> String? {
    guard let c else { return nil }
    let renews = DLTime.time(c.renewsAt)
    return c.left > 0 ? tn("emails.creditsLeft", c.left, ["time": renews]) : t("emails.noCredits", ["time": renews])
}

/// Words for an email without text (FS-E3, Q3).
func mediaWords(photos: Int, audios: Int, videos: Int) -> String? {
    if videos > 0 { return t("emails.media.video") }
    if photos > 0 { return photos > 1 ? t("emails.media.photos", ["n": photos]) : t("emails.media.photo") }
    if audios > 0 { return audios > 1 ? t("emails.media.voiceNotes", ["n": audios]) : t("emails.media.voiceNote") }
    return nil
}

func emailCountWords(_ n: Int) -> String { tn("emails.count", n) }

/// One email composer's state (FS-E11–E16; web emails/EmailComposer.tsx): an optional Subject (a new
/// email), the text with its 1024 counter, the strip with one video, one autosaved draft per key
/// (`new` or a thread id) with the letter draft's saver and conflict rule.
@MainActor
@Observable
final class EmailComposer {
    let key: String
    var withSubject: Bool { key == "new" }
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var subject = ""
    private(set) var text = ""
    private(set) var trimmed = false
    private(set) var attachments: Attachments?
    @ObservationIgnored private(set) var saver: DraftSaver!
    @ObservationIgnored let backend: Backend

    init(key: String, backend: Backend) {
        self.key = key
        self.backend = backend
        saver = DraftSaver { [weak self] version in
            guard let self else { throw CancellationError() }
            return try await backend.api.saveEmailDraft(key: key, subject: self.withSubject ? self.subject : "", text: self.text, version: version)
        }
    }

    func load() async {
        do {
            apply(try await backend.api.emailDraft(key: key))
            loaded = true
        } catch {
            failed = true
        }
    }

    func apply(_ d: EmailDraft) {
        subject = d.subject
        text = d.text
        saver.load(version: d.version, savedAt: d.savedAt)
        if let attachments { attachments.reset(d.attachments) } else {
            attachments = Attachments(d.attachments, path: "api/emails/drafts/\(key)/attachments", api: backend.api)
        }
    }

    /// Q5: typing simply stops at 1024; only an overflowing paste gets the notice.
    func changeText(_ raw: String) {
        let (next, cut) = clamp(raw)
        trimmed = cut && normalize(raw).count - text.count > 1
        guard next != text else { return }
        text = next
        saver.touch()
    }

    func changeSubject(_ raw: String) {
        subject = String(raw.replacingOccurrences(of: "\n", with: " ").prefix(subjectMax))
        saver.touch()
    }

    func loadServer() async {
        if let d = try? await backend.api.emailDraft(key: key) { apply(d) }
    }

    func deleteAttachment(_ id: String, onFail: @escaping () -> Void) {
        Task { do { try await backend.api.deleteEmailDraftAttachment(key: key, id: id) } catch { onFail() } }
    }

    enum SendResult { case sent(EmailSent), conflict, failed(String) }

    func send() async -> SendResult {
        let version: Int
        do {
            version = try await saver.flush()
        } catch let e as DraftSaver.FlushError where e.conflict {
            return .conflict
        } catch {
            return .failed(t("common.notSent"))
        }
        do {
            let sent = key == "new" ? try await backend.api.sendNewEmail(draftVersion: version)
                : try await backend.api.reply(threadId: key, draftVersion: version)
            if let next = try? await backend.api.emailDraft(key: key) { apply(next) } else {
                text = ""
                subject = ""
                attachments?.reset([])
            }
            trimmed = false
            await backend.home.load()
            return .sent(sent)
        } catch let e as APIError {
            if e.code == "NO_CREDITS" {
                backend.home.refreshSoon()
                var c = backend.home.home?.emailCredits
                c?.left = 0
                return .failed(creditsLine(c) ?? e.message)
            }
            if e.status == 422 || e.code == "VIDEO_LIMIT" { return .failed(e.message) }
            return .failed(t("common.notSent"))
        } catch {
            return .failed(t("common.notSent"))
        }
    }

    func close() {
        saver.flushOnLeave()
        saver.dispose()
    }
}

/// The composer fields (canvas "new email", "thread (reply on top)"): Subject on a new email, the
/// text with its counter, the strip, the add row (photos, video, voice) and Send.
struct ComposerView: View {
    let composer: EmailComposer
    let credits: EmailCredits?
    let onSent: (EmailSent) -> Void

    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @State private var recorder: VoiceRecorder?
    @State private var sending = false
    @State private var error: String?
    @State private var videoPick: PhotosPickerItem?
    @State private var camera = false

    var body: some View {
        let atts = composer.attachments
        let noCredits = (credits?.left ?? 1) <= 0
        let recording = recorder?.recording ?? false
        let hasVideo = atts?.has("video") ?? false
        // Subscription Tiers CM-1–CM-7: over the limit, Send is off; no videos left, the video button is.
        let limits = atts.flatMap { stripLimits(backend.home.home?.plan, mediaOf($0.items)) }
        let videoOff = limits.map { !$0.videoRoom } ?? false
        let canSend = !sending && !noCredits && !(atts?.uploading ?? false) && !recording && limits?.block == nil
            && (!composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(atts?.done.isEmpty ?? true))
            && (!composer.withSubject || !composer.subject.trimmingCharacters(in: .whitespaces).isEmpty)
        VStack(alignment: .leading, spacing: 10) {
            if composer.withSubject {
                TextField(t("emails.subject"), text: Binding(get: { composer.subject }, set: { composer.changeSubject($0) }))
                    .font(.custom(DLFontName.literataSemiBold.name, size: 18, relativeTo: .headline))
                    .foregroundStyle(.dlMailInk)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(.dlMailLine).frame(height: 1) }
            }
            TextField(composer.withSubject ? t("emails.writeAnEmail") : t("emails.reply"), text: Binding(get: { composer.text }, set: { composer.changeText($0) }), axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(.dlMailInk)
                .lineLimit(composer.withSubject ? 8 ... 30 : 3 ... 12)
            HStack {
                if composer.trimmed { Text(trimmedLine).foregroundStyle(.dlError) }
                Spacer()
                Text("\(composer.text.count)/\(emailMax)").monospacedDigit().foregroundStyle(.dlInkQuiet)
            }
            .font(.caption)
            if let atts {
                AttachmentStrip(atts, limits: limits) { item in
                    let index = atts.items.firstIndex(of: item) ?? 0
                    atts.remove(item.key)
                    if let a = item.att { composer.deleteAttachment(a.id) { atts.restore(item, at: index) } }
                }
                HStack(spacing: 0) {
                    if let recorder {
                        AddBar(
                            attachments: atts,
                            recorder: recorder,
                            enabled: !sending,
                            doodleFull: true,
                            limits: limits,
                            video: VideoCapture(off: hasVideo || videoOff) { camera = true }
                        ) {}
                            .fixedSize()
                    }
                    // Camera CA8: Record a video lives in the Camera menu; this one picks from the library.
                    PhotosPicker(selection: $videoPick, matching: .videos) {
                        Image(systemName: "film")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(hasVideo || videoOff ? Color.dlInkDisabled : Color.dlInk)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(hasVideo || recording || videoOff)
                    .accessibilityLabel(hasVideo ? t("media.videoAttachedOnePerEmail") : t("media.pickAVideo"))
                    Spacer()
                    Button(sending ? t("common.sending") : t("common.send")) { send() }
                        .buttonStyle(.borderedProminent)
                        .tint(.dlMailBlue)
                        .disabled(!canSend)
                }
            }
            if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
            if let line = creditsLine(credits) {
                Text(line).font(.caption).foregroundStyle(noCredits ? Color.dlError : Color.dlInkQuiet)
            }
        }
        .padding(16)
        .background(.dlMailBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.dlMailLine))
        .onAppear {
            if recorder == nil, let atts {
                recorder = VoiceRecorder { data, ms in atts.add(.audio, name: "voice.m4a", mime: "audio/mp4", durationMs: ms) { data } }
            }
        }
        .onChange(of: videoPick) { _, item in
            guard let item, let atts else { return }
            atts.add(.video, name: "video.mp4", mime: "video/mp4") {
                guard let movie = try await item.loadTransferable(type: Movie.self) else { throw Attachments.ReadError() }
                return try await Movie.mp4(movie.url)
            }
            videoPick = nil
        }
        .fullScreenCover(isPresented: $camera) {
            VideoCamera { url in
                camera = false
                guard let url, let atts else { return }
                atts.add(.video, name: "video.mp4", mime: "video/mp4") { try await Movie.mp4(url) }
            }
            .ignoresSafeArea()
        }
        .alert(t("emails.aNewerVersionWasSaved"), isPresented: Binding(get: { composer.saver.status == .conflict }, set: { _ in })) {
            Button(t("emails.keepMine"), role: .cancel) { composer.saver.keepMine() }
            Button(t("emails.load")) { Task { await composer.loadServer() } }
        }
    }

    private func send() {
        sending = true
        error = nil
        Task {
            switch await composer.send() {
            case let .sent(s): onSent(s)
            case .conflict: break
            case let .failed(text): error = text
            }
            sending = false
        }
    }
}

/// The thread's reply bar (doc "Delululand — Email Bubbles" EB8; web ThreadView .dl-dock): one line
/// docked at the bottom — + · the field · Send — under the credits line. + opens the tray (the strip
/// and the add row) from the bottom and turns into ×; while the bar is in use the counter joins the
/// credits line; the field grows to six lines. Reduce Motion: the same bar without the motion.
struct DockedComposerView: View {
    let composer: EmailComposer
    let credits: EmailCredits?
    let onSent: (EmailSent) -> Void

    @Environment(Backend.self) private var backend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorder: VoiceRecorder?
    @State private var sending = false
    @State private var error: String?
    @State private var videoPick: PhotosPickerItem?
    @State private var camera = false
    @State private var trayAsked = false
    @FocusState private var focused: Bool

    var body: some View {
        let atts = composer.attachments
        let noCredits = (credits?.left ?? 1) <= 0
        let recording = recorder?.recording ?? false
        let hasVideo = atts?.has("video") ?? false
        let limits = atts.flatMap { stripLimits(backend.home.home?.plan, mediaOf($0.items)) }
        let videoOff = limits.map { !$0.videoRoom } ?? false
        let canSend = !sending && !noCredits && !(atts?.uploading ?? false) && !recording && limits?.block == nil
            && (!composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(atts?.done.isEmpty ?? true))
        // The tray stays open while it holds something; the bar is open while it is in use.
        let tray = trayAsked || !(atts?.items.isEmpty ?? true) || recording
        let open = tray || focused || !composer.text.isEmpty
        let motion: Animation? = reduceMotion ? nil : .snappy(duration: 0.26)
        VStack(spacing: 6) {
            if tray, let atts {
                VStack(alignment: .leading, spacing: 6) {
                    AttachmentStrip(atts, limits: limits) { item in
                        let index = atts.items.firstIndex(of: item) ?? 0
                        atts.remove(item.key)
                        if let a = item.att { composer.deleteAttachment(a.id) { atts.restore(item, at: index) } }
                    }
                    HStack(spacing: 0) {
                        if let recorder {
                            AddBar(
                                attachments: atts,
                                recorder: recorder,
                                enabled: !sending,
                                doodleFull: true,
                                limits: limits,
                                video: VideoCapture(off: hasVideo || videoOff) { camera = true }
                            ) {}
                                .fixedSize()
                        }
                        PhotosPicker(selection: $videoPick, matching: .videos) {
                            Image(systemName: "film")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(hasVideo || videoOff ? Color.dlInkDisabled : Color.dlInk)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(hasVideo || recording || videoOff)
                        .accessibilityLabel(hasVideo ? t("media.videoAttachedOnePerEmail") : t("media.pickAVideo"))
                        Spacer(minLength: 0)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if composer.trimmed { Text(trimmedLine).font(.caption).foregroundStyle(.dlError) }
            if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
            HStack(spacing: 10) {
                if open {
                    Text("\(composer.text.count) / \(emailMax)").monospacedDigit()
                        .foregroundStyle(composer.text.count >= emailMax ? Color.dlError : Color.dlInkQuiet)
                        .transition(.opacity)
                }
                if let line = creditsLine(credits) {
                    Text(line).foregroundStyle(noCredits ? Color.dlError : Color.dlInkQuiet)
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    // Attaching is not typing (EB15): opening the tray puts the keyboard away.
                    if !tray { focused = false }
                    withAnimation(motion) { trayAsked.toggle() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.dlInk)
                        .rotationEffect(.degrees(tray ? 45 : 0))
                        .frame(width: 44, height: 44)
                        .background(Color.dlPaperLetter, in: Circle())
                        .overlay(Circle().stroke(Color.dlLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tray && trayAsked ? t("emails.closeAttachments") : t("emails.attach"))
                TextField(t("emails.writeAReply"), text: Binding(get: { composer.text }, set: { composer.changeText($0) }), axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(.dlInk)
                    .lineLimit(1 ... 6)
                    .focused($focused)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .background(Color.dlPaperLetter, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.dlLine, lineWidth: 1))
                    .accessibilityLabel(t("emails.replyLabel"))
                Button { send() } label: {
                    Group {
                        if sending {
                            ProgressView().tint(Color.dlOnSeal)
                        } else {
                            Image(systemName: "arrow.forward").font(.system(size: 17, weight: .bold)).flipsForRightToLeftLayoutDirection(true)
                        }
                    }
                    .foregroundStyle(canSend ? Color.dlOnSeal : Color.dlInkDisabled)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.dlSeal : Color.dlLine, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(sending ? t("common.sending") : t("common.send"))
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.dlLine).frame(height: 1) }
        .animation(motion, value: tray)
        .animation(motion, value: open)
        .onAppear {
            if recorder == nil, let atts {
                recorder = VoiceRecorder { data, ms in atts.add(.audio, name: "voice.m4a", mime: "audio/mp4", durationMs: ms) { data } }
            }
        }
        .onChange(of: videoPick) { _, item in
            guard let item, let atts else { return }
            atts.add(.video, name: "video.mp4", mime: "video/mp4") {
                guard let movie = try await item.loadTransferable(type: Movie.self) else { throw Attachments.ReadError() }
                return try await Movie.mp4(movie.url)
            }
            videoPick = nil
        }
        .fullScreenCover(isPresented: $camera) {
            VideoCamera { url in
                camera = false
                guard let url, let atts else { return }
                atts.add(.video, name: "video.mp4", mime: "video/mp4") { try await Movie.mp4(url) }
            }
            .ignoresSafeArea()
        }
        .alert(t("emails.aNewerVersionWasSaved"), isPresented: Binding(get: { composer.saver.status == .conflict }, set: { _ in })) {
            Button(t("emails.keepMine"), role: .cancel) { composer.saver.keepMine() }
            Button(t("emails.load")) { Task { await composer.loadServer() } }
        }
    }

    private func send() {
        sending = true
        error = nil
        Task {
            switch await composer.send() {
            case let .sent(s):
                trayAsked = false
                onSent(s)
            case .conflict: break
            case let .failed(text): error = text
            }
            sending = false
        }
    }
}

/// A picked video, copied out of the photo library.
struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appending(path: "pick-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }

    /// The clip as MP4 (H.264/AAC), for the server and every phone.
    static func mp4(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let out = FileManager.default.temporaryDirectory.appending(path: "video-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw Attachments.ReadError()
        }
        if #available(iOS 18, *) {
            try await export.export(to: out, as: .mp4)
        } else {
            export.outputURL = out
            export.outputFileType = .mp4
            await export.export()
            if export.status != .completed { throw Attachments.ReadError() }
        }
        return try Data(contentsOf: out)
    }
}

/// The system camera in video mode, at most the tier's length (Emails Q12, Subscription Tiers ST4).
struct VideoCamera: UIViewControllerRepresentable {
    let onDone: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        if picker.sourceType == .camera {
            picker.cameraCaptureMode = .video
            picker.videoMaximumDuration = TimeInterval(VideoLimits.seconds)
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (URL?) -> Void
        init(_ onDone: @escaping (URL?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}
