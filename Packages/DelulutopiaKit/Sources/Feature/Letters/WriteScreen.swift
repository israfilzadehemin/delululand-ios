import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

/// S4 Write (canvas W-Draft, W-Edit, W-Send): the draft page, or a sent letter still in its window.
/// The ruled sheet with its stamp slot, the editor with the format bar on the keyboard, the
/// attachment strip and add row. Send opens S5; a sent letter folds into its envelope and is sealed.
public struct WriteScreen: View {
    let editId: Int?
    let replyTo: Int?

    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var model: WriteModel?

    public init(editId: Int? = nil, replyTo: Int? = nil) {
        self.editId = editId
        self.replyTo = replyTo
    }

    public var body: some View {
        Group {
            if let model {
                switch model.load {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed, .notEditable:
                    VStack(spacing: 16) {
                        Text(editId == nil ? "Couldn’t load your draft. Check your connection and try again." : "This letter can’t be edited.")
                            .dlText(.callout).foregroundStyle(.dlInkQuiet).multilineTextAlignment(.center)
                        Button("Back") { dismiss() }.buttonStyle(DLButtonStyle(.outline))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    WriteForm(model: model)
                }
            } else {
                Color.dlPaper
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .task {
            if model == nil {
                let m = WriteModel(backend: backend, editId: editId, replyTo: replyTo)
                model = m
                await m.start()
            }
        }
        .onDisappear { model?.close() }
    }
}

private struct WriteForm: View {
    let model: WriteModel

    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dlSelectTab) private var selectTab
    @Environment(\.dlOpen) private var open
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor = RichEditorState()
    @State private var recorder: VoiceRecorder?
    @State private var sendOpen = false
    @State private var sealing = false
    @State private var stampOpen = false
    @State private var doodleOpen = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var lateHandled = false

    private var editing: Bool { model.letter != nil }
    private var friend: String { backend.home.home?.friend?.nickname ?? "Friend" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = DLTime.now
            content(now: now)
        }
        .onAppear {
            if recorder == nil, let atts = model.attachments {
                recorder = VoiceRecorder { data, ms in
                    atts.add(.audio, name: "voice.m4a", mime: "audio/mp4", durationMs: ms) { data }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.flushOnHide() }
            if phase == .active, !editing {
                Task { if let doc = await model.checkNewer() { editor.set(doc) } }
            }
        }
    }

    private func late(now: Date) -> Bool {
        guard let letter = model.letter else { return false }
        return DLTime.remaining(until: letter.windowEndsAt, now: now) <= 0 || model.lateByServer
    }

    private var changed: Bool {
        guard let letter = model.letter, let atts = model.attachments else { return false }
        return model.body != letter.doc || atts.done.map(\.id) != letter.attachments.map(\.id) || atts.uploading || model.stamp?.slug != letter.stamp?.slug
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let atts = model.attachments!
        let late = late(now: now)
        let recording = recorder?.recording ?? false
        let canSend = !late && !busy && (!model.empty || !atts.done.isEmpty) && !atts.uploading && !recording
        let saver = model.saver
        let savedLine: String = {
            guard let saver else { return "" }
            if saver.status == .error { return "Couldn’t save your draft" }
            if let at = saver.savedAt, saver.status != .conflict { return "Draft saved \(DLTime.time(at))" }
            return ""
        }()
        VStack(spacing: 0) {
            if let letter = model.letter {
                EditingHead(left: DLTime.remaining(until: letter.windowEndsAt, now: now), arrives: DLTime.time(letter.arrivesAt), late: late)
            }
            if model.pinned != nil, !editing {
                ReplySlip(model: model, friend: friend)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let error {
                            Text(error).dlText(.footnote).foregroundStyle(.dlError).padding(.horizontal, 20).padding(.top, 8)
                        }
                        HStack {
                            Spacer()
                            StampSlot(stamp: model.stamp, enabled: !late) {
                                model.loadStamps()
                                stampOpen = true
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        RichEditor(editor, initial: model.initial, enabled: !late, placeholder: "Dear \(friend),") { doc in
                            model.onBody(doc)
                        }
                        .padding(EdgeInsets(top: 16, leading: 20, bottom: 30, trailing: 20))
                        .frame(minHeight: 300, alignment: .top)
                        .background(alignment: .top) { WriteRules().padding(.top, 16) }
                        .contentShape(Rectangle())
                        .onTapGesture { editor.focus() }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(alignment: .leading) {
                    Rectangle().fill(.dlLetterMargin).frame(width: 1).padding(.leading, 11)
                }
                .background(.dlLetterSheet)
                .overlay(alignment: .bottomTrailing) { DogEar().scaleEffect(22 / 14, anchor: .bottomTrailing) }
                if sealing { SealOverlay(seal: Who.of(backend.home.home?.me.id, first: backend.home.home?.firstCitizen).signature) }
            }
            if !late {
                VStack(alignment: .leading, spacing: 4) {
                    AttachmentStrip(atts) { item in
                        let index = atts.items.firstIndex(of: item) ?? 0
                        atts.remove(item.key)
                        if !editing, let att = item.att {
                            model.deleteDraftAttachment(att.id) { atts.restore(item, at: index) }
                        }
                    }
                    .padding(.horizontal, 16)
                    if let recorder {
                        AddBar(attachments: atts, recorder: recorder, enabled: !late, doodleFull: atts.has("doodle")) { doodleOpen = true }
                    }
                }
                .padding(.top, 6)
                .background(.dlLetterEnvelope)
            }
        }
        .navigationTitle(editing ? "Editing a sent letter" : "To \(friend)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editing)
        .toolbar {
            if editing {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if changed { confirmDiscard = true } else { dismiss() } } label: { Image(systemName: "chevron.left") }
                        .disabled(late)
                        .accessibilityLabel("Back, discard changes")
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(editing ? "Editing a sent letter" : "To \(friend)").font(.headline)
                    if !editing, !savedLine.isEmpty {
                        Text(savedLine).font(.caption).foregroundStyle(saver?.status == .error ? Color.dlError : Color.dlInkQuiet)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Send again" : "Send") {
                    if editing { sendAgain() } else { sendOpen = true }
                }
                .buttonStyle(.borderedProminent)
                .tint(.dlSeal)
                .disabled(!canSend)
            }
        }
        .sheet(isPresented: $sendOpen) {
            SendSheet(
                delay: backend.server?.delay ?? "PT60M",
                window: backend.server?.window ?? "PT5M",
                feeling: backend.home.home.map { Moods.text($0.me.mood, emoji: $0.me.moodEmoji, label: $0.me.moodLabel) } ?? nil,
                onClose: { sendOpen = false },
                onSend: send
            )
        }
        .sheet(isPresented: $stampOpen) {
            StampPicker(model: model) { stampOpen = false }.environment(backend)
        }
        .fullScreenCover(isPresented: $doodleOpen) {
            DoodlePad(onDone: { png in
                doodleOpen = false
                atts.add(.doodle, name: "doodle.png", mime: "image/png") { png }
            }, onClose: { doodleOpen = false })
                .environment(backend)
        }
        .alert("A newer version was saved on another device. Load it?", isPresented: Binding(get: { saver?.status == .conflict }, set: { _ in })) {
            Button("Keep mine", role: .cancel) { model.keepMine() }
            Button("Load") { Task { if let doc = await model.loadServer() { editor.set(doc) } } }
        }
        .alert("Too late: the original version is on its way.", isPresented: Binding(get: { editing && late && !lateHandled }, set: { _ in })) {
            Button("Discard", role: .cancel) {
                lateHandled = true
                Task {
                    await model.discardEdit()
                    dismiss()
                }
            }
            Button("Keep text in draft") {
                lateHandled = true
                Task {
                    if await model.keepInDraft() {
                        dismiss()
                        open(.write())
                    } else {
                        error = "Couldn’t save your draft"
                    }
                }
            }
        } message: {
            Text("\(friend) gets the letter as you first sent it, at \(model.letter.map { DLTime.time($0.arrivesAt) } ?? ""). The text you changed is still here."
                + (backend.home.home?.me.draftEmpty == false ? " Keeping it replaces your current draft." : ""))
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Yes", role: .destructive) {
                Task {
                    await model.discardEdit()
                    dismiss()
                }
            }
            Button("No", role: .cancel) {}
        }
    }

    private func send() async -> String? {
        switch await model.send() {
        case .sent:
            sendOpen = false
            sealing = true
            try? await Task.sleep(for: .milliseconds(900))
            selectTab(.letters)
            return nil
        case .conflict:
            sendOpen = false
            return nil
        case let .failed(text):
            return text
        }
    }

    private func sendAgain() {
        busy = true
        error = nil
        Task {
            if let failed = await model.sendAgain() {
                busy = false
                if !failed.isEmpty { error = failed }
            } else {
                sealing = true
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            }
        }
    }
}

/// The seal-tinted line under the bar while a sent letter is being edited.
private struct EditingHead: View {
    let left: TimeInterval
    let arrives: String
    let late: Bool

    var body: some View {
        Text("\(DLTime.countdown(left)) left · arrives at \(arrives)\(late ? "" : " whatever you change")")
            .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 13, relativeTo: .footnote).monospacedDigit())
            .foregroundStyle(.dlInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.dlSealTint)
            .overlay(alignment: .bottom) { Rectangle().fill(.dlSealTintLine).frame(height: 1) }
    }
}

/// 28 pt rules from the first line to the foot of the sheet.
private struct WriteRules: View {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let step = 28 * scale
            var y = step - 1
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.dlLetterRule))
                y += step
            }
        }
        .accessibilityHidden(true)
    }
}

/// The stamp slot on the paper: a dashed outline with a plus, or the chosen stamp (FS-ST8).
private struct StampSlot: View {
    let stamp: StampMark?
    let enabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Group {
                if let stamp {
                    StampImage(url: stamp.imageUrl, name: stamp.name, width: 56)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.dlLetterEdge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 56, height: 71)
                        .overlay(Text("+").font(.system(size: 22)).foregroundStyle(.dlInkQuiet))
                }
            }
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(DLPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(stamp.map { "Stamp: \($0.name). Change it" } ?? "Add a stamp")
    }
}

/// The letter being answered (FS-W5, Replies A1–A4): a note slip clipped to the sheet. ‹ › step
/// through received letters and move the reply; × makes it a plain letter.
private struct ReplySlip: View {
    let model: WriteModel
    let friend: String

    var body: some View {
        let l = model.referenced
        let ids = model.received.map(\.id)
        let i = model.pinned.flatMap { ids.firstIndex(of: $0) }
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REPLYING TO").font(.custom(DLFontName.manropeExtraBold.rawValue, size: 11, relativeTo: .caption2)).tracking(0.77)
                    .foregroundStyle(.dlInkQuiet)
                Text(l.map { firstLineOf($0.firstLine, media: $0.media) } ?? "…")
                    .font(.custom(DLFontName.literataRegular.rawValue, size: 14, relativeTo: .body))
                    .foregroundStyle(.dlLetterInk)
                    .lineLimit(1)
                if let l {
                    Text("\(friend) · \(DLTime.clock(l.arrivesAt))").font(.caption).foregroundStyle(.dlInkQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { if let i, i > 0 { model.pin(ids[i - 1]) } } label: { Image(systemName: "chevron.left").frame(width: 32, height: 44) }
                .disabled(i == nil || i == 0)
                .accessibilityLabel("Newer received letter")
            Button {
                if let i, i + 1 < ids.count { model.pin(ids[i + 1]) } else { model.loadReceived() }
            } label: { Image(systemName: "chevron.right").frame(width: 32, height: 44) }
                .accessibilityLabel("Older received letter")
            Button { model.pin(nil) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 44) }
                .accessibilityLabel("Not a reply: send as a new letter")
        }
        .foregroundStyle(.dlInk)
        .padding(.leading, 15)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(alignment: .leading) { Rectangle().fill(.dlUserA).frame(width: 3) }
        .background(.dlLetterSlip, in: UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
        .shadow(color: .dlShade.opacity(0.15), radius: 1.5, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The letter you are answering")
        .onAppear { model.loadReceived() }
    }
}

/// S5 Send confirm (FS-S1–S3; canvas W-Send): arrival time and "in N min", until when it can be
/// edited or cancelled, the frozen mood. `onSend` returns an error line, or nil when done.
private struct SendSheet: View {
    let delay: String
    let window: String
    let feeling: String?
    let onClose: () -> Void
    let onSend: () async -> String?

    @State private var sending = false
    @State private var error: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = DLTime.now
            let d = DLTime.isoDuration(delay) ?? 3600
            let w = DLTime.isoDuration(window) ?? 300
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "envelope")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.dlSeal)
                    .frame(width: 48, height: 48)
                    .background(.dlSealTint, in: Circle())
                Text("Send this letter?").dlText(.title2).foregroundStyle(.dlInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arrives at").dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    (Text(DLTime.time(of: now.addingTimeInterval(d))).font(.custom(DLFontName.manropeExtraBold.rawValue, size: 28, relativeTo: .title).monospacedDigit())
                        + Text(" · in \(Int((d / 60).rounded())) min").font(DLTextStyle.callout.spec.dynamicFont).foregroundColor(.dlInkQuiet))
                        .foregroundStyle(.dlInk)
                }
                (Text("Until ") + Text(DLTime.time(of: now.addingTimeInterval(w))).bold() + Text(" you can still edit or cancel it from Letters or Home."))
                    .dlText(.callout).foregroundStyle(.dlInk)
                if let feeling { Text("Feeling \(feeling)").dlText(.callout).foregroundStyle(.dlInk) }
                if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
                HStack(spacing: 8) {
                    Button("Keep writing", action: onClose)
                        .buttonStyle(DLButtonStyle(.grey, fullWidth: true))
                        .disabled(sending)
                    Button(sending ? "Sending…" : "Send") {
                        sending = true
                        error = nil
                        Task {
                            if let failed = await onSend() {
                                error = failed
                                sending = false
                            }
                        }
                    }
                    .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                    .disabled(sending)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.dlSheet)
        .interactiveDismissDisabled(sending)
    }
}

/// Sent: the sheet folds into its envelope and is sealed (Letter paper story).
private struct SealOverlay: View {
    let seal: Color
    @State private var fold: Double = 0
    @State private var stamp: Double = 0

    var body: some View {
        ZStack {
            Color.dlPaper.opacity(fold)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4).fill(.dlLetterEnvelope)
                SealFlap().fill(.dlLetterFlap)
                SealFlap().stroke(.dlLetterEdge, lineWidth: 1)
                WaxSeal(color: seal, size: 30).scaleEffect(stamp).offset(y: 76)
            }
            .frame(height: 180)
            .padding(.horizontal, 60)
            .scaleEffect(x: 1, y: 0.4 + 0.6 * fold)
            .opacity(fold)
            .shadow(color: .dlShade.opacity(0.15), radius: 3, y: 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { fold = 1 }
            withAnimation(.spring(duration: 0.3).delay(0.45)) { stamp = 1 }
        }
        .accessibilityHidden(true)
    }

    private struct SealFlap: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var p = Path()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.5))
            p.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.5), control: CGPoint(x: w * 0.5, y: h * 0.58))
            p.closeSubpath()
            return p
        }
    }
}

/// The stamp picker (FS-ST1–ST8; canvas "stamp picker"): search by name or keyword, Recent, No
/// stamp, then a section per theme with a strip of theme chips to jump.
private struct StampPicker: View {
    let model: WriteModel
    let onClose: () -> Void
    @State private var query = ""

    private func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    var body: some View {
        let catalogue = model.stamps
        let all = catalogue?.stamps ?? []
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        let found = q.isEmpty ? all : all.filter { fold($0.name).contains(q) || $0.keywords.contains { fold($0).contains(q) } }
        let recent = (catalogue?.recent ?? []).compactMap { slug in all.first { $0.slug == slug } }
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.stampsFailed {
                            Text("Couldn’t load the stamps. Check your connection and try again.").dlText(.callout).foregroundStyle(.dlInkQuiet)
                        } else if catalogue == nil {
                            Text("Loading stamps…").dlText(.callout).foregroundStyle(.dlInkQuiet)
                        } else if !q.isEmpty {
                            if found.isEmpty { Text("Nothing found").dlText(.callout).foregroundStyle(.dlInkQuiet) }
                            grid(found)
                        } else {
                            if !recent.isEmpty {
                                heading("Recent")
                                grid(recent)
                            }
                            Button("No stamp") {
                                model.chooseStamp(nil)
                                onClose()
                            }
                            .buttonStyle(DLButtonStyle(.outline))
                            ForEach(catalogue?.themes ?? []) { theme in
                                heading(theme.name).id(theme.slug)
                                grid(all.filter { $0.theme == theme.slug })
                            }
                        }
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .top) {
                    if q.isEmpty, let themes = catalogue?.themes, !themes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(themes) { theme in
                                    Button(theme.name) { withAnimation { proxy.scrollTo(theme.slug, anchor: .top) } }
                                        .buttonStyle(DLButtonStyle(.tint))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .background(.bar)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search stamps")
            .navigationTitle("Stamps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DLGlassIconButton("xmark", label: "Close", action: onClose)
                }
            }
            .background(Color.dlSheet)
        }
        .presentationDetents([.large])
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 11, relativeTo: .caption2))
            .tracking(0.77)
            .foregroundStyle(.dlInkQuiet)
            .padding(.top, 6)
    }

    private func grid(_ stamps: [StampView]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(stamps) { s in
                let on = model.stamp?.slug == s.slug
                Button {
                    model.chooseStamp(s.mark)
                    onClose()
                } label: {
                    VStack(spacing: 4) {
                        StampImage(url: s.imageUrl, name: s.name, width: 60)
                            .padding(4)
                            .background(on ? Color.dlSealTint : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Color.dlSeal : .clear, lineWidth: 2))
                        Text(s.name).font(.caption2).foregroundStyle(.dlInkQuiet).lineLimit(2).multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(DLPressStyle())
                .accessibilityLabel(s.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
