import DLData
import DLDesignSystem
import DLNetwork
import DLUI
import FeatureStart
import SwiftUI

extension AppTab {
    /// The line a placeholder tab shows until its screen lands.
    var placeholderLine: String {
        switch self {
        case .home: "Home arrives in the next build."
        case .you: "You arrives in the next build."
        default: "\(title) arrive in the next build."
        }
    }
}

/// The app's root (FS-A2): the start flow until a session opens, then the tabs. Theme, tint, the
/// TEST line and the live stream's foreground life live here.
public struct AppRoot: View {
    let backend: Backend
    let initialTab: AppTab
    @Environment(\.scenePhase) var scenePhase

    public init(backend: Backend, initialTab: AppTab = .home) {
        self.backend = backend
        self.initialTab = initialTab
    }

    public var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let line = backend.testBanner { DLTestBanner(line) }
            }
            .environment(backend)
            .tint(.dlSeal)
            .preferredColorScheme(backend.settings.themeMode.colorScheme)
            .task {
                await backend.session.refresh()
                await backend.loadServerSettings()
            }
            .onChange(of: signedIn) { _, now in
                if now { backend.didSignIn() } else { backend.didSignOut() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard signedIn else { return }
                switch phase {
                case .active:
                    backend.live.start()
                    backend.home.refreshSoon()
                case .background:
                    backend.live.stop()
                default:
                    break
                }
            }
    }

    private var signedIn: Bool {
        if case .signedIn = backend.session.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch backend.session.state {
        case .unknown:
            LaunchScreen()
        case .unreachable:
            ZStack {
                Color.dlPaper.ignoresSafeArea()
                DLUnreachable(universe: "Delulutopia") { Task { await backend.session.refresh() } }
            }
        case .signedOut:
            StartFlow()
                .transition(.opacity)
        case .signedIn:
            SignedInShell(initialTab: initialTab)
                .transition(.opacity)
        }
    }
}

/// The first frame matches the static launch screen: paper, the mark, the wordmark.
struct LaunchScreen: View {
    var body: some View {
        ZStack {
            Color.dlPaper.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.dlUserA)
                    .opacity(0)
                Text("Delulutopia")
                    .font(.custom(DLFontName.literataSemiBold.rawValue, size: 18, relativeTo: .headline))
                    .foregroundStyle(.dlInk)
                    .opacity(0)
            }
            ProgressView().tint(.dlInkQuiet).offset(y: 80)
        }
    }
}

/// Signed in: the tabs, plus the one-time Face ID offer after a typed PIN (X1).
struct SignedInShell: View {
    let initialTab: AppTab
    @Environment(Backend.self) var backend
    @State private var selection: AppTab

    init(initialTab: AppTab) {
        self.initialTab = initialTab
        self._selection = State(initialValue: initialTab)
    }

    var body: some View {
        MainTabView(selection: $selection)
            .alert(
                backend.biometrics.kind == .touchID ? "Unlock with Touch ID?" : "Unlock with Face ID?",
                isPresented: Binding(get: { offerVisible }, set: { if !$0 { backend.pendingBiometricOffer = nil } })
            ) {
                Button("Not now", role: .cancel) {
                    if let offer = backend.pendingBiometricOffer { markOffered(offer.userId) }
                    backend.pendingBiometricOffer = nil
                }
                Button(backend.biometrics.kind == .touchID ? "Use Touch ID" : "Use Face ID") {
                    if let offer = backend.pendingBiometricOffer {
                        backend.biometrics.store(pin: offer.pin, userId: offer.userId)
                        markOffered(offer.userId)
                    }
                    backend.pendingBiometricOffer = nil
                }
            } message: {
                Text("Next time, \(backend.biometrics.kind == .touchID ? "touch the button" : "look at your \(deviceWord)") instead of typing your PIN. "
                    + "Your PIN stays on this \(deviceWord), opened only by \(backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID"). You can turn it off in You.")
            }
    }

    private var offerVisible: Bool {
        guard let offer = backend.pendingBiometricOffer, backend.biometrics.isAvailable else { return false }
        return !backend.biometrics.hasPin(userId: offer.userId) && !offered(offer.userId)
    }

    private func offered(_ userId: Int) -> Bool {
        UserDefaults.standard.bool(forKey: "dl.faceIDOffered.\(userId)")
    }

    private func markOffered(_ userId: Int) {
        UserDefaults.standard.set(true, forKey: "dl.faceIDOffered.\(userId)")
    }
}

extension ThemeMode {
    /// Nil follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .match: nil
        }
    }
}
