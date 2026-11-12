import SwiftUI

/// Every design-system piece on one page, for review in staging builds (You › Design system) and
/// for the CI screenshots in light and dark.
public struct DLComponentCatalog: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Type") { typeRamp }
                section("Colour roles") { swatches }
                section("Buttons") { buttons }
                section("Fields") { fields }
                section("Rows") { rows }
                section("Marks") { marks }
                section("Glass") { glass }
                section("Notes") { notes }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(.dlPaper)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DLSectionLabel(title)
            content()
        }
    }

    // MARK: Type

    private var typeRamp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discussions").dlText(.largeTitle)
            Text("Delulutopia").dlText(.title1)
            Text("Enter your PIN").dlText(.title2)
            Text("Waiting for someone to join").dlText(.title3)
            Text("To Leyla").dlText(.headline)
            Text("One tap sets it. Leyla sees it right away.").dlText(.body)
            Text("Only if we take the slow train").dlText(.callout)
            Text("Arrives 15:20").dlText(.subheadline)
            Text("Delivered 13:12 · not read yet").dlText(.footnote).foregroundStyle(.dlInkQuiet)
            Text("From Leyla").dlText(.label).foregroundStyle(.dlInkQuiet)
            Text("Dear Emin, the week went by slower than I expected. Ə ə").dlText(.letterBody)
            Text("Love the little sun. Is that Zakopane?").dlText(.handwriting)
            Text("Q7MK-2PXA-9F3T").dlText(.key)
        }
        .foregroundStyle(.dlInk)
    }

    // MARK: Colours

    private struct Swatch: Identifiable {
        let id: String
        let token: DLColorToken
    }

    private var swatches: some View {
        let roles = [
            Swatch(id: "paper", token: DLPalette.paper), Swatch(id: "cell", token: DLPalette.cell),
            Swatch(id: "sheet", token: DLPalette.sheet), Swatch(id: "letter", token: DLPalette.paperLetter),
            Swatch(id: "line", token: DLPalette.line), Swatch(id: "ink", token: DLPalette.ink),
            Swatch(id: "quiet", token: DLPalette.inkQuiet), Swatch(id: "seal", token: DLPalette.seal),
            Swatch(id: "tint", token: DLPalette.sealTint), Swatch(id: "error", token: DLPalette.error),
            Swatch(id: "user a", token: DLPalette.userA), Swatch(id: "user b", token: DLPalette.userB),
            Swatch(id: "sheet·l", token: DLPalette.letterSheet), Swatch(id: "envelope", token: DLPalette.letterEnvelope),
            Swatch(id: "new", token: DLPalette.newBadge), Swatch(id: "mail", token: DLPalette.mailBackground),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(roles) { swatch in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(swatch.token.color)
                        .frame(height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    Text(swatch.id)
                        .dlText(.footnote)
                        .foregroundStyle(.dlInkQuiet)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {} label: { Label("Write a letter", systemImage: "square.and.pencil") }
                    .buttonStyle(.dlFilled)
                Button("Keep writing") {}
                    .buttonStyle(.dlGrey)
            }
            HStack(spacing: 10) {
                Button("Edit") {}
                    .buttonStyle(.dlOutline)
                Button("Allow") {}
                    .buttonStyle(.dlTint)
                Button("Not now") {}
                    .buttonStyle(.dlText)
            }
            HStack(spacing: 10) {
                Button("Send") {}
                    .buttonStyle(.dlFilled)
                    .disabled(true)
                Button("Log out") {}
                    .buttonStyle(.dlDanger)
            }
        }
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            DLField("Username", text: .constant("Emin"), hint: "3–16 letters or digits, no spaces")
            DLField("Key", text: .constant("Q7MK-2PXA-9"), error: "That key doesn’t fit.", kind: .key)
        }
    }

    // MARK: Rows

    private var rows: some View {
        DLGroupedCard {
            DLGroupedCardRow(divider: false) {
                HStack {
                    DLRowLabel(
                        "Notifications",
                        subtitle: "9 of 12 on",
                        icon: DLRowIcon("bell.fill", tint: .dlSystemRed)
                    )
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.dlInkQuiet)
                }
            }
            DLGroupedCardRow {
                Toggle(isOn: .constant(true)) {
                    DLRowLabel("Face ID unlock")
                }
                .tint(.dlSeal)
            }
            DLGroupedCardRow {
                DLCheckRow("Light", subtitle: "Paper and navy", checked: true)
            }
            DLGroupedCardRow {
                HStack {
                    DLRowLabel("Install app")
                    DLSoonChip()
                }
            }
        }
    }

    // MARK: Marks

    private var marks: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                DLReactionChip("❤️", count: 2, mine: true) {}
                DLReactionChip("😂", mine: false) {}
                DLAddReactionButton {}
                Spacer(minLength: 12)
                DLNewBadge()
                DLNewDot()
            }
            HStack(spacing: 16) {
                DLCountdownChip("28:41")
                DLPinDots(entered: 3)
            }
            HStack(spacing: 12) {
                DLAvatar(initials: "E", size: 40, signature: .a, ring: true)
                DLAvatar(initials: "L", size: 40, signature: .b, ring: true)
                DLAvatar(initials: "N", size: 40)
                DLAvatar(initials: "E", size: 26, signature: .a)
            }
        }
    }

    // MARK: Glass

    private var glass: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                DLGlassIconButton("chevron.left", label: "Back") {}
                DLGlassIconButton("ellipsis", label: "More") {}
                DLGlassIconButton("xmark", label: "Close") {}
            }
            DLToast("Arrives at 14:50", symbol: "clock")
            DLToast("2 photos added to your draft", symbol: "photo", actionTitle: "Undo") {}
            DLDraftAccessory("Continue your letter", glass: true) {}
        }
    }

    // MARK: Notes

    private var notes: some View {
        HStack(spacing: 8) {
            ForEach(DLNoteColor.allCases) { note in
                RoundedRectangle(cornerRadius: DLRadius.card, style: .continuous)
                    .fill(note.face.color)
                    .frame(height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        Rectangle()
                            .fill(note.deep.color)
                            .frame(width: 12, height: 12)
                    }
            }
        }
    }
}

/// Glass pieces and the capsule buttons over paper content, sized to one screen so they can be
/// reviewed as drawn on a device (system glass only renders on screen).
public struct DLGlassSamples: View {
    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            DLPalette.paper.color.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous)
                        .fill(index.isMultiple(of: 3) ? Color.dlSealTint : Color.dlPaperLetter)
                        .frame(height: 64)
                        .overlay(alignment: .leading) {
                            Text(index.isMultiple(of: 2) ? "Letter from Leyla" : "Discussion · Zakopane")
                                .dlText(.subheadline)
                                .foregroundStyle(.dlInk)
                                .padding(.leading, 16)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 70)

            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    DLGlassIconButton("chevron.left", label: "Back") {}
                    Spacer()
                    DLGlassIconButton("ellipsis", label: "More") {}
                    DLGlassIconButton("xmark", label: "Close") {}
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("Edit") {}
                        .buttonStyle(.dlOutline)
                    Button("Allow") {}
                        .buttonStyle(.dlTint)
                    Button("Send") {}
                        .buttonStyle(.dlFilled)
                    Button("Keep") {}
                        .buttonStyle(.dlGrey)
                }
                .padding(12)
                .background(.dlPaper, in: RoundedRectangle(cornerRadius: DLRadius.groupedCard, style: .continuous))
                DLToast("Arrives at 14:50", symbol: "clock")
                DLToast("2 photos added to your draft", symbol: "photo", actionTitle: "Undo") {}
                DLDraftAccessory("Continue your letter", glass: true) {}
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}
