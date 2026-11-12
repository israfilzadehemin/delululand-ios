import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI

/// S3 (web home/MoodSheet.tsx; canvas A-Mood): the universe's moods — the 32 defaults, then its own —
/// in pages of 8 (4 × 2) with "+ New mood" last (disabled at the limit). Swipe for the next page;
/// dots and ‹ › show where you are. Opens on the page holding the current mood, which is marked.
/// One tap sets it and closes. Each custom mood has a ✎ that opens its form, with Delete inside.
struct MoodSheet: View {
    let current: String?
    let friend: String?
    let friendMood: String?
    let actions: HomeActions
    let onClose: () -> Void

    @Environment(Backend.self) private var backend
    @State private var page = 0
    @State private var form: MoodForm.Mode?
    @State private var busy = false
    @State private var error = false

    private var moods: [Mood] { backend.home.moods }
    private var limit: Int { backend.home.moodLimit }
    private var canAdd: Bool { backend.home.moodsLoaded }
    private var full: Bool { moods.count >= limit }

    private var pages: [[Mood?]] {
        let entries: [Mood?] = canAdd ? moods.map { Optional($0) } + [nil] : moods.map { Optional($0) }
        return stride(from: 0, to: entries.count, by: Moods.perPage).map { Array(entries[$0 ..< min($0 + Moods.perPage, entries.count)]) }
    }

    var body: some View {
        Group {
            if let form {
                MoodForm(mode: form, current: current, friend: friend, friendMood: friendMood, actions: actions) { newPage in
                    self.form = nil
                    if let newPage { page = newPage }
                }
            } else {
                grid
            }
        }
        .presentationDetents([.height(form == nil ? 400 : 470)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.dlSheet)
        .onAppear {
            if let i = moods.firstIndex(where: { $0.key == current }) { page = i / Moods.perPage }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How do you feel?")
                    .font(.custom(DLFontName.manropeBold.rawValue, size: 18, relativeTo: .title3))
                    .foregroundStyle(.dlInk)
                Spacer()
                DLGlassIconButton("xmark", label: "Close", action: onClose)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { p in
                    pageView(pages[p]).tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 76 * 2 + 10)

            HStack(spacing: 16) {
                pageArrow("chevron.left", "Previous moods", enabled: page > 0) { page -= 1 }
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { p in
                        Capsule()
                            .fill(p == page ? Color.dlSeal : Color.dlLine)
                            .frame(width: p == page ? 18 : 6, height: 6)
                            .onTapGesture { withAnimation { page = p } }
                            .accessibilityLabel("Mood page \(p + 1)")
                    }
                }
                .animation(DLMotion.easeOut(0.2), value: page)
                pageArrow("chevron.right", "More moods", enabled: page < pages.count - 1) { page += 1 }
            }
            .padding(.top, 12)

            Text(foot)
                .dlText(.footnote)
                .foregroundStyle(error ? Color.dlError : Color.dlInkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private var foot: String {
        if error { return "Not saved. Try again." }
        if canAdd, full { return "\(limit) of \(limit) — delete one to add another" }
        if let friend { return "One tap sets it. \(friend) sees it right away, not after an hour." }
        return "One tap sets it."
    }

    private func pageArrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.dlInk : Color.dlInkDisabled)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func pageView(_ entries: [Mood?]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(entries.enumerated()), id: \.offset) { i, mood in
                Group {
                    if let mood {
                        tile(mood)
                    } else {
                        newTile
                    }
                }
                .dlEnter(.popIn, delay: min(0.22, 0.08 + 0.02 * Double(i)))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ mood: Mood) -> some View {
        let on = mood.key == current
        return Button {
            busy = true
            error = false
            Task {
                if await actions.setMood(mood.key) {
                    onClose()
                } else {
                    error = true
                    busy = false
                }
            }
        } label: {
            VStack(spacing: 6) {
                Text(mood.emoji).font(.system(size: 26))
                Text(mood.label)
                    .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 12, relativeTo: .caption))
                    .foregroundStyle(.dlInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
            .background(on ? Color.dlSealTint : Color.dlPaper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.dlSeal : Color.dlLine, lineWidth: on ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(DLPressStyle())
        .disabled(busy)
        .accessibilityLabel("\(mood.emoji) \(mood.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            if mood.custom {
                Button { form = .edit(mood) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.dlInkQuiet)
                        .frame(width: 24, height: 24)
                        .background(.dlPaper, in: Circle())
                        .overlay(Circle().strokeBorder(.dlLine))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Edit \(mood.label)")
            }
        }
    }

    private var newTile: some View {
        let enabled = !busy && !full
        return Button { form = .new } label: {
            VStack(spacing: 6) {
                Text("+").font(.system(size: 26)).foregroundStyle(enabled ? Color.dlSeal : Color.dlInkDisabled)
                Text("New mood")
                    .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 12, relativeTo: .caption))
                    .foregroundStyle(.dlInkQuiet)
            }
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
            .background(.dlPaper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.dlInkDisabled, style: StrokeStyle(lineWidth: 1, dash: [6, 6])))
        }
        .buttonStyle(DLPressStyle())
        .disabled(!enabled)
    }
}

/// The add / edit form (web home/MoodForm.tsx; canvas "New mood", "Edit mood"): one emoji from the
/// emoji keyboard, a label of up to 16 characters checked as you type, Save; editing adds Delete
/// with a confirm that says who is wearing it. ‹ goes back to the grid.
struct MoodForm: View {
    enum Mode: Equatable {
        case new
        case edit(Mood)
    }

    let mode: Mode
    let current: String?
    let friend: String?
    let friendMood: String?
    let actions: HomeActions
    let onDone: (Int?) -> Void

    @Environment(Backend.self) private var backend
    @State private var emoji = ""
    @State private var label = ""
    @State private var picking = false
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?

    private var editing: Mood? {
        if case let .edit(m) = mode { return m }
        return nil
    }

    private var catalogue: [Mood] { backend.home.moods }

    var body: some View {
        let problem = Moods.labelProblem(label, catalogue: catalogue, exceptKey: editing?.key)
        let count = Moods.labelLength(label)
        let unchanged = editing.map { emoji == $0.emoji && Moods.normalise(label) == $0.label } ?? false
        let canSave = !emoji.isEmpty && count > 0 && problem == nil && !busy && !unchanged
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                Button { onDone(nil) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.dlInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Back to moods")
                Text(editing != nil ? "Edit mood" : "New mood").dlText(.title3).foregroundStyle(.dlInk)
                Spacer()
            }
            .padding(.top, 10)

            VStack(spacing: 6) {
                EmojiInput(emoji: $emoji, isEditing: $picking) {
                    Text(emoji.isEmpty ? "+" : emoji)
                        .font(.system(size: 36))
                        .foregroundStyle(emoji.isEmpty ? Color.dlSeal : Color.dlInk)
                        .frame(width: 72, height: 72)
                        .background(.dlPaper, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(picking ? Color.dlSeal : Color.dlLine, lineWidth: picking ? 2 : 1))
                }
                .accessibilityLabel(emoji.isEmpty ? "Choose an emoji" : "Emoji \(emoji). Change it")
                .accessibilityAddTraits(.isButton)
                if emoji.isEmpty {
                    Text("Choose an emoji").dlText(.footnote).foregroundStyle(.dlInkQuiet)
                }
            }

            DLField(
                "Label",
                text: Binding(get: { label }, set: { value in
                    if value.count <= 40 { label = value }
                    error = nil
                }),
                hint: Moods.labelRule,
                error: problem,
                counter: "\(count)/\(Moods.labelMax)"
            )
            .disabled(busy)

            if let error {
                Text(error).dlText(.footnote).foregroundStyle(.dlError).multilineTextAlignment(.center)
            }

            Button(busy && !confirm ? "Saving…" : "Save") { save() }
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .disabled(!canSave)

            if editing != nil {
                Button("Delete mood", role: .destructive) { confirm = true }
                    .buttonStyle(DLButtonStyle(.text))
                    .foregroundStyle(.dlError)
                    .disabled(busy)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .onAppear {
            emoji = editing?.emoji ?? ""
            label = editing?.label ?? ""
        }
        .confirmationDialog("Delete this mood?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Yes, delete", role: .destructive) { delete() }
            Button("No", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        guard let editing else { return "" }
        let meWears = current == editing.key
        let friendWears = friend != nil && friendMood == editing.key
        var text = "“\(editing.emoji) \(editing.label)” goes from the sheet\(friend != nil ? " for both of you" : ""). Letters already sent keep it."
        if meWears, friendWears, let friend {
            text += "\n\nYou and \(friend) are feeling this right now. Deleting it clears your moods."
        } else if friendWears, let friend {
            text += "\n\n\(friend) is feeling this right now. Deleting it clears their mood."
        } else if meWears {
            text += "\n\nYou’re feeling this right now. Deleting it clears your mood."
        }
        return text
    }

    private func save() {
        busy = true
        error = nil
        let size = catalogue.count
        Task {
            switch await actions.saveMood(editing: editing, emoji: emoji, label: label) {
            case .success:
                onDone(editing == nil ? size / Moods.perPage : nil)
            case let .failure(e):
                error = e.text
                busy = false
            }
        }
    }

    private func delete() {
        guard let editing else { return }
        busy = true
        error = nil
        Task {
            if let failed = await actions.deleteMood(editing.key) {
                error = failed
                busy = false
            } else {
                onDone(nil)
            }
        }
    }
}
