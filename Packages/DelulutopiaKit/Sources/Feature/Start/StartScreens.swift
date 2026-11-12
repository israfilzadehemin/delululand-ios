import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import SwiftUI
import UIKit

public enum StartRoute: Hashable, Sendable {
    case pin(userId: Int)
    case create
    case join
}

/// Everything before a session (canvas row "Start, key and PIN" and "Create or join"): the key, the
/// cards, the PIN, and creating or joining a universe. A session opening ends the flow (the shell
/// switches to the tabs).
public struct StartFlow: View {
    @Environment(Backend.self) private var backend
    @State private var path: [StartRoute]
    @State private var entry: EntryModel?

    /// `path` opens the flow part-way in (screenshots).
    public init(path: [StartRoute] = []) {
        _path = State(initialValue: path)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let entry {
                    EntryScreen(model: entry, path: $path)
                } else {
                    Color.dlPaper
                }
            }
            .navigationDestination(for: StartRoute.self) { route in
                switch route {
                case let .pin(userId):
                    PinScreen(userId: userId) { path.removeAll() }
                case .create:
                    CreateUniverseFlow { path.removeAll() }
                case .join:
                    JoinFlow {
                        path.removeAll()
                        Task { await entry?.load() }
                    }
                }
            }
        }
        .tint(.dlInk)
        .task {
            if entry == nil {
                let model = EntryModel(backend: backend)
                entry = model
                await model.load()
            }
        }
    }
}

// MARK: - Entry: landing and cards

struct EntryScreen: View {
    @Bindable var model: EntryModel
    @Binding var path: [StartRoute]
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            switch model.content {
            case .loading:
                ProgressView().controlSize(.large).tint(.dlInkQuiet)
            case .unreachable:
                DLUnreachable(universe: "Delulutopia") { Task { await model.load() } }
            case .landing:
                landing
            case let .cards(view):
                cards(view)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: Binding(get: { model.welcome.map(WelcomeItem.init) }, set: { if $0 == nil { model.welcome = nil } })) { item in
            WelcomeSheet(name: item.entered.name, welcome: item.entered.welcome, preview: false) { model.welcome = nil }
        }
    }

    private var landing: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Delulutopia")
                        .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 28, relativeTo: .title))
                        .foregroundStyle(.dlInk)
                    Text("Enter your universe’s key.")
                        .dlText(.subheadline)
                        .foregroundStyle(.dlInkQuiet)
                }
                .padding(.top, 120)
                .padding(.bottom, 16)
                .dlEnter(.rise)

                DLField(
                    "Key",
                    text: Binding(get: { model.key }, set: { model.setKey($0) }),
                    prompt: "XXXX-XXXX-XXXX",
                    error: model.wrong ? "That key doesn’t fit." : (model.offline ? "Can’t reach Delulutopia. Try again." : nil),
                    kind: .key
                )
                .focused($keyFocused)
                .submitLabel(.go)
                .onSubmit { Task { await model.submit() } }
                .dlEnter(.rise, delay: 0.08)

                Button {
                    Task { await model.submit() }
                } label: {
                    if model.busy { ProgressView().tint(.dlOnSeal) } else { Text("Enter") }
                }
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .disabled(model.busy || model.key.isEmpty)
                .dlEnter(.rise, delay: 0.12)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Text("Have an invite?").dlText(.subheadline).foregroundStyle(.dlInk)
                DLStrongLink("Create a universe") { path.append(.create) }
            }
            .padding(.bottom, 8)
        }
    }

    private func cards(_ view: EntryView) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(view.name)
                    .dlText(.title1)
                    .foregroundStyle(.dlInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 96)
                    .padding(.bottom, 24)
                    .dlEnter(.rise)
                ForEach(Array(view.users.enumerated()), id: \.element.id) { i, user in
                    CardButton { path.append(.pin(userId: user.id)) } content: {
                        DLRemoteAvatar(url: user.avatarUrl, name: user.nickname, size: 88, signature: signature(forIndex: i), ring: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.nickname)
                                .font(.custom(DLFontName.manropeSemiBold.rawValue, size: 20, relativeTo: .title3))
                                .foregroundStyle(.dlInk)
                            Text(user.hasPin ? "Tap to enter" : "Tap to set your PIN")
                                .dlText(.footnote)
                                .foregroundStyle(.dlInkQuiet)
                        }
                    }
                    .dlEnter(.rise, delay: 0.12 + 0.08 * Double(i))
                }
                if view.canJoin {
                    CardButton { path.append(.join) } content: {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .foregroundStyle(.dlInkQuiet)
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(.dlInkQuiet))
                            .padding(.horizontal, 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join \(view.name)")
                                .font(.custom(DLFontName.manropeBold.rawValue, size: 18, relativeTo: .headline))
                                .foregroundStyle(.dlInk)
                            Text("Create your citizen").dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        }
                    }
                    .dlEnter(.rise, delay: 0.12 + 0.08 * Double(view.users.count))
                }
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            DLStrongLink("Use a different key") { Task { await model.forget() } }
                .padding(.bottom, 8)
        }
    }

    private struct WelcomeItem: Identifiable {
        let entered: Entered
        var id: String { entered.name }
    }
}

/// A card on the cards screen: 12 pt corners, letter paper, a hairline, presses to 98 %.
private struct CardButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                content
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(.dlPaperLetter, in: RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous).strokeBorder(.dlLine, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous))
        }
        .buttonStyle(DLPressStyle(scale: 0.98))
    }
}

/// UV-3: "Welcome to <name>" with the universe's paragraphs; Enter only (Close for the creator's preview).
struct WelcomeSheet: View {
    let name: String
    let welcome: String
    let preview: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Welcome to \(name)")
                        .dlText(.title1)
                        .foregroundStyle(.dlInk)
                        .padding(.top, 28)
                    ForEach(Array(StartRules.paragraphs(welcome).enumerated()), id: \.offset) { i, p in
                        Text(p)
                            .dlText(.letterBody)
                            .foregroundStyle(.dlInk)
                            .dlEnter(.rise, delay: 0.06 * Double(i + 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            Button(preview ? "Close" : "Enter", action: onDone)
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(.dlSheet)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!preview)
    }
}

// MARK: - PIN

struct PinScreen: View {
    let userId: Int
    let onLeave: () -> Void
    @Environment(Backend.self) private var backend
    @State private var model: PinModel?
    @State private var askedBiometrics = false

    var body: some View {
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            if let model {
                PinBody(model: model)
                    .padding(.top, 58)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onChange(of: model.leave) { _, leave in if leave { onLeave() } }
                    .task {
                        await model.load()
                        if model.canUseBiometrics && !askedBiometrics {
                            askedBiometrics = true
                            await model.unlockWithBiometrics()
                        }
                    }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .onAppear {
            if model == nil { model = PinModel(userId: userId, backend: backend) }
        }
    }
}

private struct PinBody: View {
    @Bindable var model: PinModel
    @Environment(Backend.self) private var backend

    private var prompt: String {
        switch model.mode {
        case .enter: "Enter your PIN"
        case .create: "Create your PIN"
        case .confirm: "Confirm your PIN"
        }
    }

    var body: some View {
        DLPinPanel(
            prompt: prompt,
            hint: model.mode == .create ? "Six digits. You will confirm it once." : nil,
            error: problemText(model.problem, universe: model.universe),
            digits: Binding(get: { model.digits }, set: { model.digits = $0; model.typed($0) }),
            busy: model.busy || model.user == nil,
            biometric: model.canUseBiometrics ? backend.biometrics.kind : nil,
            onBiometric: { Task { await model.unlockWithBiometrics() } },
            onComplete: { model.complete($0) }
        ) {
            if let user = model.user {
                DLRemoteAvatar(url: user.avatarUrl, name: user.nickname, size: 96, signature: signature(forIndex: model.index), ring: true)
            } else {
                Circle().fill(.dlPlaceholder).frame(width: 96, height: 96)
            }
        }
    }
}

func problemText(_ problem: PinModel.Problem?, universe: String) -> String? {
    switch problem {
    case nil: nil
    case .wrong: "Wrong PIN. Try again."
    case .differ: "PINs differ. Start again."
    case .offline: "Can’t reach \(universe.isEmpty ? "Delulutopia" : universe). Try again."
    case let .text(text): text
    }
}

// MARK: - Wizards (create and join)

/// The wizard chrome (canvas U-*): back on the left, the step dots in the middle, the step's content
/// with a Literata title, and its primary button pinned at the bottom.
private struct WizardScaffold<Content: View, Bottom: View>: View {
    let step: Int
    let of: Int
    let showDots: Bool
    let onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let bottom: Bottom

    var body: some View {
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .bottom) {
            bottom
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(onBack != nil)
        .toolbarRole(.editor)
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back")
                }
            }
            if showDots {
                ToolbarItem(placement: .principal) { DLStepDots(step: step, of: of) }
            }
        }
    }
}

private struct FormColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct WizardTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom(DLFontName.literataSemiBold.rawValue, size: 30, relativeTo: .title))
            .foregroundStyle(.dlInk)
            .dlEnter(.rise)
    }
}

struct CreateUniverseFlow: View {
    let onLeave: () -> Void
    @Environment(Backend.self) private var backend
    @State private var model: CreateUniverseModel?

    var body: some View {
        Group {
            if let model { CreateUniverseSteps(model: model, onLeave: onLeave) } else { Color.dlPaper }
        }
        .onAppear { if model == nil { model = CreateUniverseModel(backend: backend) } }
    }
}

private struct CreateUniverseSteps: View {
    @Bindable var model: CreateUniverseModel
    let onLeave: () -> Void

    var body: some View {
        switch model.step {
        case 1:
            WizardScaffold(step: 1, of: 4, showDots: true, onBack: nil) {
                FormColumn {
                    WizardTitle(text: "Your invite")
                    Text("A universe starts with an invite. Each invite makes one universe.")
                        .dlText(.body)
                        .foregroundStyle(.dlInk)
                    DLField(
                        "Invite",
                        text: Binding(get: { model.invite }, set: { model.setInvite($0) }),
                        prompt: "XXXX-XXXX-XXXX",
                        error: model.inviteProblem == .wrong ? "That invite doesn’t work."
                            : (model.inviteProblem == .offline ? "Can’t reach Delulutopia. Try again." : nil),
                        kind: .key
                    )
                    .submitLabel(.go)
                    .onSubmit { Task { await model.checkInvite() } }
                    HStack(spacing: 4) {
                        Text("Have a key instead?").dlText(.subheadline).foregroundStyle(.dlInk)
                        DLStrongLink("Enter it", action: onLeave)
                    }
                }
            } bottom: {
                Button {
                    Task { await model.checkInvite() }
                } label: {
                    if model.busy { ProgressView().tint(.dlOnSeal) } else { Text("Continue") }
                }
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .disabled(model.busy || model.invite.isEmpty)
            }
        case 2:
            WizardScaffold(step: 2, of: 4, showDots: true, onBack: { _ = model.back() }) {
                FormColumn {
                    WizardTitle(text: "Your universe")
                    let typed = model.name.trimmingCharacters(in: .whitespaces)
                    DLField(
                        "Name",
                        text: Binding(get: { model.name }, set: { model.setName($0) }),
                        hint: "2–12 letters or digits. Shown wherever the app’s name shows.",
                        error: model.nameServerError ?? ((!model.name.isEmpty && !StartRules.nameOK(model.name)) ? "2–12 letters or digits" : nil),
                        counter: "\(typed.count)/12"
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    let shownName = typed.isEmpty ? "your universe" : typed
                    DLField(
                        "Welcome message",
                        text: Binding(get: { model.welcome }, set: { model.setWelcome($0) }),
                        hint: model.welcomeEdited
                            ? "Shown under “Welcome to \(shownName)” when a key is entered."
                            : "Shown under “Welcome to \(shownName)” when a key is entered. Follows the name until you edit it.",
                        error: model.welcomeEdited ? model.welcomeError : nil,
                        counter: "\(StartRules.welcomeLength(model.welcome).formatted())/1,500",
                        multilineMinHeight: 196
                    )
                    HStack {
                        Button("See it as your friend will") { model.preview = true }
                            .font(.custom(DLFontName.manropeExtraBold.rawValue, size: 15, relativeTo: .subheadline))
                            .foregroundStyle(.dlSeal)
                            .disabled(model.welcomeError != nil)
                        Spacer()
                        if model.welcomeEdited {
                            Button("Reset to the original") { model.resetWelcome() }
                                .font(.custom(DLFontName.manropeBold.rawValue, size: 15, relativeTo: .subheadline))
                                .foregroundStyle(.dlInkQuiet)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
                .sheet(isPresented: $model.preview) {
                    WelcomeSheet(name: shownNameForPreview, welcome: model.welcome, preview: true) { model.preview = false }
                }
            } bottom: {
                Button("Continue") { model.next() }
                    .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                    .disabled(!StartRules.nameOK(model.name) || model.welcomeError != nil)
            }
        case 3:
            WizardScaffold(step: 3, of: 4, showDots: true, onBack: { _ = model.back() }) {
                FormColumn {
                    WizardTitle(text: "Your citizen")
                    CitizenStep(citizen: $model.citizen, taken: [], serverError: model.citizenError, signatureIndex: 0)
                }
            } bottom: {
                Button("Continue") { model.next() }
                    .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                    .disabled(!StartRules.usernameOK(model.citizen.username))
            }
        case 4:
            WizardScaffold(step: 4, of: 4, showDots: true, onBack: { _ = model.back() }) {
                WizardPinStep(
                    who: "\(model.citizen.username) · \(model.name.trimmingCharacters(in: .whitespaces))",
                    pin: $model.pin,
                    universe: model.name,
                    onComplete: { model.pinComplete($0) }
                )
            } bottom: {
                EmptyView()
            }
        default:
            WizardScaffold(step: 4, of: 4, showDots: false, onBack: nil) {
                FormColumn {
                    if let created = model.created {
                        KeyReveal(name: created.name, code: created.code) { Task { await model.finish() } }
                    }
                }
            } bottom: {
                EmptyView()
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private var shownNameForPreview: String {
        let typed = model.name.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? "your universe" : typed
    }
}

struct JoinFlow: View {
    let onLeave: () -> Void
    @Environment(Backend.self) private var backend
    @State private var model: JoinModel?

    var body: some View {
        Group {
            if let model { JoinSteps(model: model, onLeave: onLeave) } else { Color.dlPaper }
        }
        .onAppear {
            if model == nil {
                let m = JoinModel(backend: backend)
                model = m
                Task { await m.load() }
            }
        }
    }
}

private struct JoinSteps: View {
    @Bindable var model: JoinModel
    let onLeave: () -> Void

    var body: some View {
        Group {
            if model.step == 1 {
                WizardScaffold(step: 1, of: 2, showDots: true, onBack: nil) {
                    FormColumn {
                        WizardTitle(text: "Your citizen")
                        CitizenStep(citizen: $model.citizen, taken: model.taken, serverError: model.serverError, signatureIndex: 1)
                    }
                } bottom: {
                    Button("Continue") { model.step = 2 }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(!model.loaded || !StartRules.usernameOK(model.citizen.username)
                            || StartRules.usernameTaken(model.citizen.username, taken: model.taken))
                }
            } else {
                WizardScaffold(step: 2, of: 2, showDots: true, onBack: { _ = model.back() }) {
                    WizardPinStep(
                        who: "\(model.citizen.username) · \(model.name)",
                        pin: $model.pin,
                        universe: model.name,
                        onComplete: { model.pinComplete($0) }
                    )
                } bottom: {
                    EmptyView()
                }
            }
        }
        .navigationTitle("Join \(model.name.isEmpty ? "Delulutopia" : model.name)")
        .onChange(of: model.leave) { _, leave in if leave { onLeave() } }
    }
}

private struct WizardPinStep: View {
    let who: String
    @Binding var pin: WizardPin
    let universe: String
    let onComplete: (String) -> Void

    var body: some View {
        DLPinPanel(
            prompt: pin.confirming ? "Confirm your PIN" : "Create your PIN",
            hint: pin.confirming ? nil : "Six digits. You will confirm it once.",
            error: problemText(pin.problem, universe: universe),
            digits: Binding(get: { pin.digits }, set: { pin.digits = $0; if !$0.isEmpty { pin.problem = nil } }),
            busy: pin.busy,
            onComplete: onComplete
        ) {
            Text(who)
                .font(.custom(DLFontName.manropeBold.rawValue, size: 18, relativeTo: .headline))
                .foregroundStyle(.dlInk)
                .frame(minHeight: 24)
        }
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// C3 and J1: username, time zone and an optional photo.
struct CitizenStep: View {
    @Binding var citizen: CitizenDraft
    let taken: [String]
    let serverError: String?
    let signatureIndex: Int
    @State private var choosing = false

    private var usernameProblem: String? {
        if let serverError { return serverError }
        if citizen.username.isEmpty { return nil }
        if !StartRules.usernameOK(citizen.username) { return "3–16 letters or digits, no spaces" }
        if StartRules.usernameTaken(citizen.username, taken: taken) { return "That username is taken" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    if let data = citizen.photo, let image = UIImage(data: data) {
                        DLAvatar(initials: "", image: Image(uiImage: image), size: 96, signature: signature(forIndex: signatureIndex), ring: true)
                    } else {
                        DLAvatar(
                            initials: citizen.username.isEmpty ? "?" : String(citizen.username.prefix(1)),
                            size: 96, signature: signature(forIndex: signatureIndex), ring: true
                        )
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        choosing = true
                    } label: {
                        Label(citizen.photo == nil ? "Add photo" : "Change photo", systemImage: "camera")
                    }
                    .buttonStyle(.dlOutline)
                    Text(citizen.photo == nil ? "Optional. Initials until then." : "Uploaded once you are in.")
                        .dlText(.footnote)
                        .foregroundStyle(.dlInkQuiet)
                }
            }
            DLField(
                "Username",
                text: Binding(get: { citizen.username }, set: { citizen.username = $0.filter { !$0.isWhitespace } }),
                hint: "3–16 letters or digits, no spaces",
                error: usernameProblem
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            DLTimeZoneField(zone: citizen.timezone, hint: "This device’s zone, picked for you.") { citizen.timezone = $0 }
            Text("Name, surname and everything else can wait for Profile.")
                .dlText(.footnote)
                .foregroundStyle(.dlInkQuiet)
        }
        .dlPhotoChooser(
            isPresented: $choosing,
            hasPhoto: citizen.photo != nil,
            onPhoto: { citizen.photo = $0 },
            onRemove: { citizen.photo = nil }
        )
    }
}

/// C5 (canvas U-Key): the key, shown once, with Copy and Share (the system share sheet). Continue
/// opens after either, or after three seconds, so nobody leaves without at least seeing it.
struct KeyReveal: View {
    let name: String
    let code: String
    var continueTitle = "Continue"
    let onContinue: () -> Void
    @State private var copied = false
    @State private var ready = false

    var body: some View {
        let grouped = groupKey(code)
        VStack(alignment: .leading, spacing: 18) {
            Text("This is \(name)’s key")
                .font(.custom(DLFontName.literataSemiBold.rawValue, size: 30, relativeTo: .title))
                .foregroundStyle(.dlInk)
                .dlEnter(.rise)
            Text(grouped)
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.dlInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(.dlCell, in: RoundedRectangle(cornerRadius: DLRadius.field, style: .continuous))
                .accessibilityLabel("Key " + code.map(String.init).joined(separator: " "))
                .dlEnter(.stamp, delay: 0.1)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = grouped
                    copied = true
                    ready = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.dlOutline)
                ShareLink(item: "\(name)’s key: \(grouped)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dlOutline)
                .simultaneousGesture(TapGesture().onEnded { ready = true })
            }
            Text("Send it to the one person you want here.")
                .dlText(.body)
                .foregroundStyle(.dlInk)
            Text("It’s shown only now. Lost it? Make a new one in You › Universe.")
                .dlText(.footnote)
                .foregroundStyle(.dlInkQuiet)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.dlPaperLetter, in: RoundedRectangle(cornerRadius: DLRadius.row, style: .continuous))
            Button(continueTitle, action: onContinue)
                .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                .disabled(!ready)
                .padding(.top, 8)
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            ready = true
        }
    }
}
