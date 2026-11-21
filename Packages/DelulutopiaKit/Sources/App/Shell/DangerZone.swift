import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

/// Doc "Delululand — Data Deletion" DD10: where deletion and privacy requests go (Pre-publish Checklist A2).
let privacyContact = "emin@delulutopia.com"

/// DL-1–DL-3 (iOS artboards DD-Y*, DD-C*, DD-P*): the last section of You. The creator deletes the
/// universe (both accounts, types the name), the second citizen only their own account. Confirm sheet
/// with counts, then the PIN — never Face ID (DD7). On success the session turns `.gone` and AppRoot
/// shows the goodbye screen.
struct DangerZoneSection: View {
    let brand: String
    @Environment(Backend.self) private var backend
    @Environment(\.openURL) private var openURL
    @State private var confirming = false
    @State private var pinFor: String?

    var body: some View {
        if case let .signedIn(s) = backend.session.state {
            let creator = s.universe.isCreator
            let friend = s.friend?.nickname
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(intro(creator: creator, friend: friend))
                        .dlText(.footnote)
                        .foregroundStyle(.dlInkQuiet)
                    Button(creator ? t("deletion.deleteUniverse", ["brand": brand]) : t("deletion.deleteMyAccount")) {
                        confirming = true
                    }
                    .buttonStyle(DLButtonStyle(.danger, fullWidth: true))
                }
                .padding(.vertical, 6)
                .dlListRow()
            } header: {
                Text(t("deletion.dangerZone").uppercased()).dlText(.label).foregroundStyle(.dlSystemRed)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Button(t("deletion.privacy")) { openURL(backend.config.apiBaseURL.appending(path: "privacy")) }
                        .dlText(.footnoteStrong)
                    Text(t("deletion.questions", ["email": privacyContact])).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                }
            }
            .sheet(isPresented: $confirming) {
                DeletionConfirmSheet(creator: creator, brand: brand) { name in
                    confirming = false
                    pinFor = name
                }
                .environment(backend)
            }
            .sheet(isPresented: Binding(get: { pinFor != nil }, set: { if !$0 { pinFor = nil } })) {
                DeletionPinSheet(creator: creator, name: pinFor ?? "").environment(backend)
            }
        }
    }

    private func intro(creator: Bool, friend: String?) -> String {
        if creator, let friend { return t("deletion.ownerText", ["brand": brand, "friend": friend]) }
        if creator { return t("deletion.ownerAloneText", ["brand": brand]) }
        return t("deletion.memberText", ["brand": brand, "friend": friend ?? t("common.friend")])
    }
}

/// DD-C*: what goes and what stays; the creator types the universe's name to continue.
struct DeletionConfirmSheet: View {
    let creator: Bool
    let brand: String
    let onContinue: (String) -> Void
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var preview: DeletionPreview?
    @State private var name = ""

    var body: some View {
        let friend = preview?.friend
        let nameOK = !creator || name.trimmingCharacters(in: .whitespaces) == brand
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(creator ? t("deletion.confirmUniverseTitle", ["brand": brand]) : t("deletion.confirmMeTitle"))
                        .dlText(.title3).foregroundStyle(.dlInk)
                    Spacer()
                    DLGlassIconButton("xmark", label: t("universe.close")) { dismiss() }
                }
                if creator, let friend {
                    Text(t("deletion.friendLoses", ["friend": friend])).dlText(.subheadlineBold).foregroundStyle(.dlSystemRed)
                }
                Text(t("deletion.thisDeletes")).dlText(.callout).foregroundStyle(.dlInk)
                VStack(alignment: .leading, spacing: 8) {
                    bullet(t(creator ? (friend != nil ? "deletion.list.profiles" : "deletion.list.profileAlone") : "deletion.list.profile"))
                    if let counts = preview?.counts {
                        ForEach(DeletionPreview.Counts.keys.filter { counts.of($0) > 0 }, id: \.self) { key in
                            HStack {
                                Text(t("deletion.count.\(key)")).dlText(.callout)
                                Spacer()
                                Text("\(counts.of(key))").dlText(.subheadlineBold).monospacedDigit()
                            }
                            .foregroundStyle(.dlInk)
                            .padding(.leading, 18)
                        }
                    }
                    bullet(t(creator ? "deletion.list.universeRest" : "deletion.list.memberRest"))
                }
                Text(kept(friend: friend)).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                if creator {
                    DLField(t("deletion.typeName", ["brand": brand]), text: $name, prompt: brand)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button(t("deletion.continue")) { onContinue(name.trimmingCharacters(in: .whitespaces)) }
                    .buttonStyle(DLButtonStyle(.danger, fullWidth: true))
                    .disabled(!nameOK)
                Button(creator ? t("app.cancel") : t("deletion.keep")) { dismiss() }
                    .buttonStyle(DLButtonStyle(.text, fullWidth: true))
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationBackground(.dlSheet)
        .task { preview = try? await backend.session.deletionPreview() }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
        }
        .dlText(.callout)
        .foregroundStyle(.dlInk)
    }

    private func kept(friend: String?) -> String {
        if creator {
            return [friend.map { t("deletion.friendNotified", ["friend": $0]) }, t("deletion.keptOwner")]
                .compactMap { $0 }.joined(separator: " ")
        }
        return t("deletion.keptMember", ["brand": brand, "friend": friend ?? t("common.friend")])
    }
}

/// DD-P*: deleted on the sixth digit; no Face ID button (DD7). One quiet retry on `PIN_THROTTLED`.
struct DeletionPinSheet: View {
    let creator: Bool
    let name: String
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(t("deletion.pinTitle")).dlText(.title3).foregroundStyle(.dlInk)
                Spacer()
                DLGlassIconButton("xmark", label: t("universe.close")) { dismiss() }.disabled(busy)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            DLPinPanel(prompt: t("pin.enterYourPin"), hint: t("deletion.pinLine"), error: error, digits: $digits, busy: busy, onComplete: submit) {
                EmptyView()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.dlSheet)
        .interactiveDismissDisabled(busy)
    }

    private func submit(_ pin: String) {
        busy = true
        error = nil
        Task {
            do {
                try await backend.retryingThrottle("PIN_THROTTLED") {
                    if creator {
                        try await backend.session.deleteUniverse(pin: pin, name: name)
                    } else {
                        try await backend.session.deleteMe(pin: pin)
                    }
                }
            } catch let e as APIError {
                error = e.code == "WRONG_PIN" || e.code == "PIN_THROTTLED"
                    ? t("common.wrongPin")
                    : ((400 ..< 500).contains(e.status) ? e.message : t("deletion.failed"))
                digits = ""
                busy = false
            } catch {
                self.error = t("deletion.failed")
                digits = ""
                busy = false
            }
        }
    }
}

/// G1–G4 (iOS artboards DD-G*): in place of the app once the device is wiped. Done → start.
struct GoodbyeScreen: View {
    let reason: String
    let brand: String?
    let onDone: () -> Void

    var body: some View {
        let b = brand ?? "Delulutopia"
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 40))
                    .foregroundStyle(.dlInkQuiet)
                Text(t("deletion.goodbye.\(reason)Title", ["brand": b]))
                    .dlText(.title2).foregroundStyle(.dlInk).multilineTextAlignment(.center)
                Text(t("deletion.goodbye.\(reason)Text", ["brand": b]))
                    .dlText(.body).foregroundStyle(.dlInkQuiet).multilineTextAlignment(.center)
                Button(t("deletion.done"), action: onDone)
                    .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                    .padding(.top, 8)
            }
            .padding(32)
        }
    }
}
