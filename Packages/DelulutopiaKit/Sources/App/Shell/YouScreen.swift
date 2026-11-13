import DLData
import DLDesignSystem
import DLI18n
import DLUI
import SwiftUI
import UIKit

enum YouRoute: Hashable {
    case appearance
    case designSystem
}

/// The You tab (iOS design F-You). PR #1 carries what works without signing in: Appearance, the
/// design-system page on staging builds, and the build's version and server. Profile, Universe,
/// Notifications, Face ID, Change PIN and Log out arrive in PR #2.
struct YouScreen: View {
    let config: AppConfig
    let settings: DeviceSettings
    @Environment(Backend.self) private var backend
    @Environment(\.dlOpen) private var open
    @Environment(\.dlNotice) private var notice
    @State private var confirmLogout = false
    @State private var changePin = false
    @State private var faceIDOn = false

    var body: some View {
        let me = backend.home.home?.me
        let brand = backend.home.home?.universe.name ?? "Delulutopia"
        let bio = backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID"
        List {
            if let me {
                Section {
                    Button { open(.profile) } label: {
                        HStack(spacing: 14) {
                            CitizenAvatar(me, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(me.nickname).dlText(.headline).foregroundStyle(.dlInk)
                                let full = [me.firstName, me.lastName].compactMap { $0 }.joined(separator: " ")
                                Text(full.isEmpty ? t("settings.viewProfile") : full).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
                        }
                    }
                    .dlListRow()
                    if let friend = backend.home.home?.friend {
                        Button { open(.friend) } label: {
                            HStack(spacing: 12) {
                                CitizenAvatar(friend, size: 32)
                                Text(t("home.sProfile", ["nickname": friend.nickname])).dlText(.callout).foregroundStyle(.dlInk)
                                Spacer()
                                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
                            }
                        }
                        .dlListRow()
                    }
                }
            }
            Section {
                row(t("settings.universe"), subtitle: t("settings.nameWelcomeKey", ["brand": brand]), symbol: "globe.europe.africa.fill", tint: .dlPostmarkHue) { open(.universe) }
                row(t("settings.appearance"), subtitle: settings.themeMode.title, symbol: "paintpalette.fill", tint: .dlSeal) { open(.appearance) }
                row(t("settings.language"), subtitle: I18n.shared.lang.native, symbol: "character.bubble.fill", tint: .dlUserB) { open(.language) }
                row(t("settings.notifications"), subtitle: nil, symbol: "bell.badge.fill", tint: .dlSystemRed) { open(.notifications) }
            } header: { DLSectionLabel(t("settings.settings")) }
            Section {
                Button { changePin = true } label: {
                    DLRowLabel(t("settings.changePin"), icon: DLRowIcon("key.fill", tint: .dlInkQuiet))
                }
                .dlListRow()
                if backend.biometrics.isAvailable, let me {
                    Toggle(isOn: Binding(get: { faceIDOn }, set: { on in
                        if on { changePin = false; turnOnBiometrics(me.id) } else { backend.biometrics.remove(userId: me.id); faceIDOn = false }
                    })) {
                        DLRowLabel(t("settings.bioUnlock", ["bio": bio]), subtitle: t("settings.bioSub", ["device": deviceWord]), icon: DLRowIcon("faceid", tint: .dlUserB))
                    }
                    .tint(.dlSeal)
                    .dlListRow()
                    .onAppear { faceIDOn = backend.biometrics.isEnabled(userId: me.id) }
                }
                HStack {
                    DLRowLabel(t("settings.about"), icon: DLRowIcon("info.circle.fill", tint: .dlInkDisabled))
                    Spacer()
                    DLSoonChip()
                }
                .opacity(0.6)
                .dlListRow()
            } header: { DLSectionLabel(t("settings.account")) }
            if config.isStaging {
                Section {
                    NavigationLink(value: YouRoute.designSystem) {
                        DLRowLabel("Design system", subtitle: "Every component, light and dark", icon: DLRowIcon("square.grid.2x2.fill", tint: .dlPostmarkHue))
                    }
                    .dlListRow()
                }
            }
            Section {
                Button(role: .destructive) { confirmLogout = true } label: {
                    DLRowLabel(t("settings.logOut"), icon: DLRowIcon("rectangle.portrait.and.arrow.forward", tint: .dlSystemRed))
                }
                .dlListRow()
            }
            Section {
                aboutRow(t("settings.version"), value: "\(config.version) (\(config.build))")
                aboutRow(t("settings.server"), value: config.apiBaseURL.host() ?? config.apiBaseURL.absoluteString)
            } header: { DLSectionLabel(t("settings.about")) }
        }
        .dlGroupedList()
        .navigationTitle(t("settings.you"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: YouRoute.self) { route in
            switch route {
            case .appearance: AppearanceScreen(settings: settings)
            case .designSystem:
                DLComponentCatalog().navigationTitle("Design system").navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog(t("app.logOutOf", ["brand": brand]), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(t("settings.logOut"), role: .destructive) { Task { await backend.session.logout() } }
            Button(t("settings.cancel"), role: .cancel) {}
        } message: {
            Text(t("app.yourLettersAndDraftsStayDevice", ["device": deviceWord]))
        }
        .sheet(isPresented: $changePin) { ChangePinSheet().environment(backend) }
        .sheet(isPresented: Binding(get: { biometricAsk != nil }, set: { if !$0 { biometricAsk = nil } })) {
            if let id = biometricAsk {
                BiometricPinSheet(userId: id) { ok in
                    biometricAsk = nil
                    faceIDOn = ok
                    if ok { notice(.text(t("settings.bioOn", ["bio": backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID"]))) }
                }
                .environment(backend)
            }
        }
    }

    private func turnOnBiometrics(_ userId: Int) {
        backend.pendingBiometricOffer = nil
        biometricAsk = userId
    }

    @State private var biometricAsk: Int?

    private func row(_ title: String, subtitle: String?, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                DLRowLabel(title, subtitle: subtitle, icon: DLRowIcon(symbol, tint: tint))
                Spacer()
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
            }
        }
        .dlListRow()
    }

    private func aboutRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).dlText(.callout).foregroundStyle(.dlInk)
            Spacer()
            Text(value).dlText(.callout).foregroundStyle(.dlInkQuiet)
        }
        .accessibilityElement(children: .combine)
        .dlListRow()
    }
}

/// Appearance (web S2): Light / Dark / Match device, saved on this device only.
public struct AppearanceScreen: View {
    let settings: DeviceSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(settings: DeviceSettings) {
        self.settings = settings
    }

    public var body: some View {
        List {
            Section {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        settings.setThemeMode(mode)
                    } label: {
                        DLCheckRow(mode.title, subtitle: mode.subtitle, checked: settings.themeMode == mode)
                    }
                    .buttonStyle(.plain)
                    .dlListRow()
                }
            }
            Section {
                Toggle(isOn: Binding(get: { settings.leaves }, set: { settings.setLeaves($0) })) {
                    DLRowLabel(t("settings.seasonalEffects"), subtitle: reduceMotion ? t("settings.leavesReducedDevice", ["device": DeviceWord.current]) : t("settings.leaves"))
                }
                .tint(.dlSeal)
                .dlListRow()
            } footer: {
                Text(t("settings.savedOnThisDeviceOnly", ["device": DeviceWord.current]))
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
            }
        }
        .dlGroupedList()
        .navigationTitle(t("settings.appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ThemeMode {
    var title: String {
        switch self {
        case .light: t("settings.theme.light")
        case .dark: t("settings.theme.dark")
        case .match: t("settings.theme.match")
        }
    }

    /// Web copy; "your phone or computer" becomes this device (iOS design §7).
    @MainActor
    var subtitle: String {
        switch self {
        case .light: t("settings.theme.lightSub")
        case .dark: t("settings.theme.darkSub")
        case .match: t("settings.theme.matchSubDevice", ["device": DeviceWord.current])
        }
    }
}

/// "iPhone" or "iPad", for copy that names this device (iOS design §7: "This phone" → "This iPhone").
@MainActor
enum DeviceWord {
    static var current: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}
