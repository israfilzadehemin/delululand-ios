import DLData
import DLDesignSystem
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
                                Text(full.isEmpty ? "View profile" : full).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
                        }
                    }
                    .dlListRow()
                    if let friend = backend.home.home?.friend {
                        Button { open(.friend) } label: {
                            HStack(spacing: 12) {
                                CitizenAvatar(friend, size: 32)
                                Text("\(friend.nickname)’s profile").dlText(.callout).foregroundStyle(.dlInk)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
                            }
                        }
                        .dlListRow()
                    }
                }
            }
            Section {
                row("Universe", subtitle: "\(brand) · name, welcome, key", symbol: "globe.europe.africa.fill", tint: .dlPostmarkHue) { open(.universe) }
                row("Appearance", subtitle: settings.themeMode.title, symbol: "paintpalette.fill", tint: .dlSeal) { open(.appearance) }
                row("Notifications", subtitle: nil, symbol: "bell.badge.fill", tint: .dlSystemRed) { open(.notifications) }
            } header: { DLSectionLabel("Settings") }
            Section {
                Button { changePin = true } label: {
                    DLRowLabel("Change PIN", icon: DLRowIcon("key.fill", tint: .dlInkQuiet))
                }
                .dlListRow()
                if backend.biometrics.isAvailable, let me {
                    Toggle(isOn: Binding(get: { faceIDOn }, set: { on in
                        if on { changePin = false; turnOnBiometrics(me.id) } else { backend.biometrics.remove(userId: me.id); faceIDOn = false }
                    })) {
                        DLRowLabel("\(bio) unlock", subtitle: "Instead of typing your PIN on this \(deviceWord)", icon: DLRowIcon("faceid", tint: .dlUserB))
                    }
                    .tint(.dlSeal)
                    .dlListRow()
                    .onAppear { faceIDOn = backend.biometrics.isEnabled(userId: me.id) }
                }
                HStack {
                    DLRowLabel("About", icon: DLRowIcon("info.circle.fill", tint: .dlInkDisabled))
                    Spacer()
                    DLSoonChip()
                }
                .opacity(0.6)
                .dlListRow()
            } header: { DLSectionLabel("Account") }
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
                    DLRowLabel("Log out", icon: DLRowIcon("rectangle.portrait.and.arrow.right", tint: .dlSystemRed))
                }
                .dlListRow()
            }
            Section {
                aboutRow("Version", value: "\(config.version) (\(config.build))")
                aboutRow("Server", value: config.apiBaseURL.host() ?? config.apiBaseURL.absoluteString)
            } header: { DLSectionLabel("About") }
        }
        .dlGroupedList()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: YouRoute.self) { route in
            switch route {
            case .appearance: AppearanceScreen(settings: settings)
            case .designSystem:
                DLComponentCatalog().navigationTitle("Design system").navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog("Log out of \(brand)?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { Task { await backend.session.logout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your letters and drafts stay safe. You’ll need your PIN to come back on this \(deviceWord).")
        }
        .sheet(isPresented: $changePin) { ChangePinSheet().environment(backend) }
        .sheet(isPresented: Binding(get: { biometricAsk != nil }, set: { if !$0 { biometricAsk = nil } })) {
            if let id = biometricAsk {
                BiometricPinSheet(userId: id) { ok in
                    biometricAsk = nil
                    faceIDOn = ok
                    if ok { notice(.text("\(backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID") unlock is on")) }
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
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.dlInkDisabled)
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
            } footer: {
                Text("Saved on this \(DeviceWord.current) only.")
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
            }
        }
        .dlGroupedList()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ThemeMode {
    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .match: "Match device"
        }
    }

    /// Web copy; "your phone or computer" becomes this device (iOS design §7).
    @MainActor
    var subtitle: String {
        switch self {
        case .light: "Paper and navy"
        case .dark: "Dusk paper, cream ink"
        case .match: "Follows this \(DeviceWord.current)"
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
