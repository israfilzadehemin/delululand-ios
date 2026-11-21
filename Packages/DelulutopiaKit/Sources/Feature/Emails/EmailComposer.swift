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

/// The quote of an email already on screen, built the way the server builds `replyTo` (Email Replies RE11).
func quoteOf(_ e: Email) -> EmailQuote {
    let oneLine = e.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    let photos = e.attachments.filter { $0.kind == "photo" }.count
    let audios = e.attachments.filter { $0.kind == "audio" }.count
    let videos = e.attachments.filter { $0.kind == "video" }.count
    let visual = e.attachments.first { ($0.kind == "photo" || $0.kind == "video") && $0.thumbUrl != nil }
    let thumb = visual?.expired == true ? nil : visual?.thumbUrl
    return EmailQuote(
        id: e.id,
        senderId: e.senderId,
        text: oneLine.isEmpty ? nil : String(oneLine.unicodeScalars.prefix(120)),
        media: ThreadMedia(photos: photos, audios: audios, videos: videos),
        thumbUrl: thumb,
        thumbExpired: visual?.expired == true,
        sentAt: e.sentAt,
        sticker: e.sticker?.url256
    )
}

/// RE9, RE11: the quote's text, else "Sticker" (FS-SK15), else "Photo" / "Voice note" / "Video".
func quoteLine(_ q: EmailQuote) -> String {
    q.text ?? (q.sticker != nil ? t("stickers.sticker") : nil)
        ?? mediaWords(photos: q.media?.photos ?? 0, audios: q.media?.audios ?? 0, videos: q.media?.videos ?? 0) ?? ""
}

/// RE6: the distance (pt) that arms a reply, and the most a bubble follows the finger.
let swipeArm: CGFloat = 64
let swipeMax: CGFloat = 96

/// Where the bubble sits for a finger moved by `dx`: toward the column's centre only (`toward` +1 =
/// trailing, −1 = leading), eased past the arm point, never past the max. Same as web replyGesture.
func swipeOffset(_ dx: CGFloat, toward: CGFloat) -> CGFloat {
    let along = dx * toward
    guard along > 0 else { return 0 }
    let eased = along <= swipeArm ? along : swipeArm + (along - swipeArm) * 0.35
    return min(swipeMax, eased) * toward
}

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
    /// Email Replies RE10: the email this reply answers, saved with the draft.
    private(set) var replyTo: EmailQuote?
    /// RE8: bumped when a reply is picked, so the bar puts the cursor in the field.
    private(set) var focusAsk = 0
    @ObservationIgnored private(set) var saver: DraftSaver!
    @ObservationIgnored let backend: Backend
    /// Optimistic send for thread replies (doc "Delululand — Optimistic Send" OS1); nil on New email.
    @ObservationIgnored let outbox: EmailOutbox?
    /// OS7: what the draft holds while an email of this thread is in the air or failed.
    @ObservationIgnored private var hold: EmailOutbox.Snapshot?
    private var releasing = false
    @ObservationIgnored private var listener: UUID?

    var optimistic: Bool { outbox != nil && !withSubject }
    /// OS3–OS7: this thread's email in the air or failed.
    var unsent: EmailOutbox.Entry? { optimistic ? outbox?.entry(key) : nil }
    /// OS7: Send and + wait while it is unresolved.
    var held: Bool { optimistic && (unsent != nil || releasing) }
    /// OS11: emails in the air have spent their credit already.
    var inAir: Int { outbox?.sendingCount ?? 0 }

    init(key: String, backend: Backend, outbox: EmailOutbox? = nil) {
        self.key = key
        self.backend = backend
        self.outbox = outbox
        saver = DraftSaver { [weak self] version in
            guard let self else { throw CancellationError() }
            if let h = self.hold {
                return try await backend.api.saveEmailDraft(key: key, subject: "", text: h.text, version: version, replyToId: h.replyToId)
            }
            return try await backend.api.saveEmailDraft(
                key: key,
                subject: self.withSubject ? self.subject : "",
                text: self.text,
                version: version,
                replyToId: self.withSubject ? nil : self.replyTo?.id
            )
        }
        if let outbox, key != "new" {
            outbox.bind(key) { [weak self] in
                guard let self else { throw CancellationError() }
                self.saver.touch()
                return try await self.saver.flush()
            }
            listener = outbox.listen { [weak self] threadId, r in
                guard let self, threadId == self.key else { return }
                Task { await self.release(r) }
            }
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
        // OS10: opened while one is in the air or failed: the draft is that email, the screen starts empty.
        let e = unsent
        hold = e?.snapshot
        subject = d.subject
        text = e == nil ? d.text : ""
        replyTo = e == nil ? d.replyTo : nil
        saver.load(version: d.version, savedAt: d.savedAt)
        let shown = e == nil ? d.attachments : []
        if let attachments { attachments.reset(shown) } else {
            attachments = Attachments(shown, path: "api/emails/drafts/\(key)/attachments", api: backend.api)
        }
    }

    /// OS3: the bubble shows at once; the composer clears and the send runs behind it.
    func sendOptimistic(senderId: PublicID) {
        guard let outbox, let atts = attachments else { return }
        let snap = EmailOutbox.Snapshot(text: text, replyToId: replyTo?.id)
        let email = outbox.provisional(threadId: key, senderId: senderId, text: text, attachments: atts.done, replyTo: replyTo)
        hold = snap
        text = ""
        replyTo = nil
        trimmed = false
        atts.reset([])
        outbox.enqueue(email, snapshot: snap, api: backend.api) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.saver.flush()
        }
    }

    /// Sent or cancelled: the draft is free again; what was typed meanwhile becomes the draft.
    private func release(_ r: EmailOutbox.Resolution) async {
        releasing = true
        var cancelled = false
        if case let .cancelled(ids) = r {
            cancelled = true
            for id in ids { try? await backend.api.deleteEmailDraftAttachment(key: key, id: id) }
        }
        let d = try? await backend.api.emailDraft(key: key)
        hold = nil
        saver.load(version: d?.version ?? saver.version, savedAt: d?.savedAt)
        // OS6: Cancel overwrites the held text; otherwise save only what is worth keeping.
        if cancelled || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replyTo != nil { saver.touch() }
        releasing = false
        await backend.home.load()
    }

    /// Q5: typing simply stops at 1024; only an overflowing paste gets the notice.
    func changeText(_ raw: String) {
        let (next, cut) = clamp(raw)
        trimmed = cut && normalize(raw).count - text.count > 1
        guard next != text else { return }
        text = next
        if hold == nil { saver.touch() }
    }

    /// RE6–RE8: answer this email; a new pick replaces the last.
    func pickReply(_ quote: EmailQuote) {
        guard !withSubject else { return }
        replyTo = quote
        if hold == nil { saver.touch() }
        focusAsk += 1
    }

    /// RE9: × on the strip.
    func cancelReply() {
        replyTo = nil
        if hold == nil { saver.touch() }
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
                replyTo = nil
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
        if let outbox, optimistic {
            outbox.unbind(key)
            if let listener { outbox.unlisten(listener) }
            listener = nil
        }
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
                // The add buttons (and Send) first; the attachments under them, grouped by type.
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
                        // Never let the tool row squeeze the label into one letter per line (F4).
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                        .buttonStyle(.borderedProminent)
                        .tint(.dlMailBlue)
                        .disabled(!canSend)
                }
                AttachmentStrip(atts, limits: limits, retentionDays: backend.server?.retention?.otherDays, stacked: true) { item in
                    let index = atts.items.firstIndex(of: item) ?? 0
                    atts.remove(item.key)
                    if let a = item.att { composer.deleteAttachment(a.id) { atts.restore(item, at: index) } }
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
    /// Email Replies RE9: "You" or the friend's name, and the colour key, for the strip.
    var quoteName: (PublicID) -> String = { _ in "" }
    var quoteWho: (PublicID) -> Who = { _ in .a }
    /// Stickers SK1: thread replies only; nil where there is no thread.
    var stickers: StickerStore?
    var onSticker: (Sticker) -> Void = { _ in }
    let onSent: (EmailSent) -> Void

    @Environment(Backend.self) private var backend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// SK10: the sticker picker sits where the keyboard was; typing closes it.
    @State private var pickerOpen = false
    @State private var adding = false
    @State private var deleting: Sticker?
    @State private var recorder: VoiceRecorder?
    @State private var sending = false
    @State private var error: String?
    @State private var videoPick: PhotosPickerItem?
    @State private var camera = false
    @State private var trayAsked = false
    @FocusState private var focused: Bool

    var body: some View {
        let atts = composer.attachments
        let recording = recorder?.recording ?? false
        let hasVideo = atts?.has("video") ?? false
        let limits = atts.flatMap { stripLimits(backend.home.home?.plan, mediaOf($0.items)) }
        let videoOff = limits.map { !$0.videoRoom } ?? false
        // OS11: the credits line drops at once while an email is in the air.
        let shown: EmailCredits? = {
            guard var c = credits, composer.inAir > 0 else { return credits }
            c.left = max(0, c.left - composer.inAir)
            c.used += composer.inAir
            return c
        }()
        let held = composer.held
        let noCredits = (shown?.left ?? 1) <= 0
        let canSend = !sending && !noCredits && !(atts?.uploading ?? false) && !recording && limits?.block == nil && !held
            && (!composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(atts?.done.isEmpty ?? true))
        // The tray stays open while it holds something; the bar is open while it is in use.
        let tray = trayAsked || !(atts?.items.isEmpty ?? true) || recording
        let open = tray || focused || pickerOpen || !composer.text.isEmpty || composer.replyTo != nil
        let motion: Animation? = reduceMotion ? nil : .snappy(duration: 0.26)
        VStack(spacing: 6) {
            if tray, let atts {
                VStack(alignment: .leading, spacing: 6) {
                    // The add buttons first, centred; the attachments under them, grouped by type.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
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
                    AttachmentStrip(atts, limits: limits, retentionDays: backend.server?.retention?.otherDays, stacked: true) { item in
                        let index = atts.items.firstIndex(of: item) ?? 0
                        atts.remove(item.key)
                        if let a = item.att { composer.deleteAttachment(a.id) { atts.restore(item, at: index) } }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if composer.trimmed { Text(trimmedLine).font(.caption).foregroundStyle(.dlError) }
            if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
            // OS7: why Send waits.
            if held, let unsent = composer.unsent, open {
                Text(unsent.status == .sending ? t("emails.waitPrevious") : t("emails.resolveUnsent"))
                    .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let q = composer.replyTo {
                ReplyStrip(quote: q, name: quoteName(q.senderId), who: quoteWho(q.senderId)) { withAnimation(motion) { composer.cancelReply() } }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // The credits, centred on their own line; open, the counter follows, start-aligned.
            if let line = creditsLine(shown) {
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(noCredits ? Color.dlError : Color.dlInkQuiet)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if open {
                Text("\(composer.text.count) / \(emailMax)").monospacedDigit()
                    .font(.system(size: 12))
                    .foregroundStyle(composer.text.count >= emailMax ? Color.dlError : Color.dlInkQuiet)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
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
                .disabled(held)
                .opacity(held ? 0.4 : 1)
                .accessibilityLabel(tray && trayAsked ? t("emails.closeAttachments") : t("emails.attach"))
                TextField(t("emails.writeAReply"), text: Binding(get: { composer.text }, set: { composer.changeText($0) }), axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(.dlInk)
                    .lineLimit(1 ... 6)
                    .focused($focused)
                    .padding(.leading, 16).padding(.trailing, stickers == nil ? 16 : 44).padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .background(Color.dlPaperLetter, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.dlLine, lineWidth: 1))
                    .accessibilityLabel(t("emails.replyLabel"))
                    .overlay(alignment: .bottomTrailing) {
                        if stickers != nil {
                            Button {
                                if pickerOpen {
                                    pickerOpen = false
                                    focused = true
                                } else {
                                    // Picking is not typing: the keyboard goes, the picker takes its place.
                                    focused = false
                                    trayAsked = false
                                    withAnimation(motion) { pickerOpen = true }
                                }
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 20))
                                    .foregroundStyle(pickerOpen ? Color.dlSeal : Color.dlInkQuiet)
                                    .frame(width: 36, height: 36)
                                    .background(pickerOpen ? Color.dlSealTint : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(held)
                            .padding(.trailing, 4).padding(.bottom, 4)
                            .accessibilityLabel(t("stickers.stickers"))
                            .accessibilityAddTraits(pickerOpen ? .isSelected : [])
                        }
                    }
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
            if pickerOpen, let stickers {
                StickerPicker(
                    store: stickers,
                    disabled: noCredits || held,
                    onPick: onSticker,
                    onAdd: { adding = true },
                    onDelete: { deleting = $0 }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.dlLine).frame(height: 1) }
        .animation(motion, value: tray)
        .animation(motion, value: open)
        .animation(motion, value: composer.replyTo?.id)
        // RE8: a picked reply puts the cursor in the field (unlike +, EB15).
        .onChange(of: composer.focusAsk) { focused = true }
        .onChange(of: focused) { _, on in if on { pickerOpen = false } }
        .animation(motion, value: pickerOpen)
        .task { stickers?.load(backend) }
        .sheet(isPresented: $adding) {
            if let stickers { AddSticker(store: stickers) { adding = false }.environment(backend) }
        }
        // FS-SK25: "Delete this sticker for both of you? Sent ones stay."
        .alert(
            t("stickers.deleteTitle"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { s in
            Button(t("stickers.delete"), role: .destructive) {
                Task {
                    if await stickers?.delete(s.id) != true { error = t("common.somethingWentWrong") }
                }
            }
            Button(t("stickers.cancel"), role: .cancel) {}
        } message: { _ in
            Text(t("stickers.deleteBody"))
        }
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
        // OS8: a conflict while held is reconciled by the send itself.
        .alert(t("emails.aNewerVersionWasSaved"), isPresented: Binding(get: { composer.saver.status == .conflict && !composer.held }, set: { _ in })) {
            Button(t("emails.keepMine"), role: .cancel) { composer.saver.keepMine() }
            Button(t("emails.load")) { Task { await composer.loadServer() } }
        }
    }

    private func send() {
        if composer.optimistic {
            // OS3: the bubble appears now; the bar is free at once.
            guard let me = backend.home.home?.me.id else { return }
            error = nil
            trayAsked = false
            composer.sendOptimistic(senderId: me)
            return
        }
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
