import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI
import UIKit
import UserNotifications

/// Profile (doc "Delululand — Menu, Profile & Settings" §3): the photo (choose or take, crop,
/// remove), username, name, surname, time zone; Save.
struct ProfileScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @State private var profile: Profile?
    @State private var username = ""
    @State private var first = ""
    @State private var last = ""
    @State private var zone = TimeZone.current.identifier
    @State private var busy = false
    @State private var photoBusy = false
    @State private var choosing = false
    @State private var error: String?
    @State private var confirmRemove = false

    var body: some View {
        let friend = backend.home.home?.friend?.nickname ?? t("settings.yourFriend")
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        DLRemoteAvatar(url: profile.avatarUrl, name: profile.username, size: 72, signature: .a, ring: true)
                            .overlay { if photoBusy { ProgressView() } }
                        VStack(alignment: .leading, spacing: 6) {
                            Button(t("profile.changePhoto"), systemImage: "camera") { choosing = true }
                                .buttonStyle(DLButtonStyle(.tint))
                            if profile.avatarUrl != nil {
                                Button(t("profile.remove"), systemImage: "trash", role: .destructive) { confirmRemove = true }
                                    .foregroundStyle(.dlError)
                            }
                        }
                        .disabled(photoBusy)
                    }
                    DLField(t("profile.username"), text: $username)
                    DLField(t("settings.name"), text: $first)
                    DLField(t("profile.surname"), text: $last)
                    DLTimeZoneField(zone: zone) { zone = $0 }
                    Text(t("profile.yourUsernameIsWhatSees", ["friend": friend]))
                        .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
                    Button(busy ? t("common.saving") : t("common.save")) { save() }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(t("profile.profile"))
        .navigationBarTitleDisplayMode(.inline)
        .dlPhotoChooser(isPresented: $choosing, hasPhoto: profile?.avatarUrl != nil, onPhoto: upload) { confirmRemove = true }
        .confirmationDialog(t("profile.removeYourPhoto"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(t("profile.remove"), role: .destructive) {
                Task {
                    photoBusy = true
                    if let p = try? await backend.api.removeAvatar() { profile = p; backend.home.refreshSoon() }
                    photoBusy = false
                }
            }
            Button(t("profile.keepIt"), role: .cancel) {}
        } message: { Text(t("profile.yourInitialsShowInsteadFor", ["friend": friend])) }
        .task {
            guard profile == nil, let p = try? await backend.api.profile() else { return }
            profile = p
            username = p.username
            first = p.firstName ?? ""
            last = p.lastName ?? ""
            zone = p.timezone
        }
    }

    private func upload(_ jpeg: Data) {
        Task {
            photoBusy = true
            do {
                profile = try await backend.api.uploadAvatar(jpeg: jpeg)
                backend.home.refreshSoon()
            } catch let e as APIError {
                notice(.text(e.isOffline ? t("media.uploadFailed") : e.message))
            } catch {
                notice(.text(t("media.uploadFailed")))
            }
            photoBusy = false
        }
    }

    private func save() {
        busy = true
        error = nil
        Task {
            do {
                profile = try await backend.api.saveProfile(username: username.trimmingCharacters(in: .whitespaces), firstName: first, lastName: last, timezone: zone)
                backend.home.refreshSoon()
                notice(.text(t("profile.saved")))
            } catch let e as APIError where (400 ..< 500).contains(e.status) {
                error = e.message
            } catch {
                self.error = t("common.notSavedTryAgain")
            }
            busy = false
        }
    }
}

/// The friend's profile: picture, names, local time, mood.
struct FriendScreen: View {
    @Environment(Backend.self) private var backend

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = DLTime.now
            if let f = backend.home.home?.friend {
                List {
                    Section {
                        VStack(spacing: 10) {
                            CitizenAvatar(f, size: 96)
                            Text(f.nickname).dlText(.title2).foregroundStyle(.dlInk)
                            let full = [f.firstName, f.lastName].compactMap { $0 }.joined(separator: " ")
                            Text(full.isEmpty ? t("profile.noNameAdded") : full).dlText(.subheadline).foregroundStyle(.dlInkQuiet)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        if let tz = f.timezone {
                            let wall = DLTime.wallClock(now, zone: tz)
                            fact(t("profile.localTime"), localDigits(String(format: "%02d:%02d", wall.hour, wall.minute)) + " · " + DLTime.city(of: tz))
                        }
                        fact(t("profile.mood"), f.moodText.map { "\($0) · \(ageWords(f.moodSetAt, now: now))" } ?? t("profile.noMoodYet"))
                    }
                }
                .dlGroupedList()
            }
        }
        .navigationTitle(backend.home.home?.friend?.nickname ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).dlText(.callout).foregroundStyle(.dlInkQuiet)
            Spacer()
            Text(value).dlText(.callout).foregroundStyle(.dlInk)
        }
        .dlListRow()
    }
}

/// Settings › Universe (doc "Delululand — Universe" §2.6): the creator renames, edits the welcome
/// and makes a new key; the other citizen reads.
struct UniverseScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @State private var view: UniverseView?
    @State private var name = ""
    @State private var welcome = ""
    @State private var busy = false
    @State private var confirmKey = false
    @State private var newKey: String?

    var body: some View {
        ScrollView {
            if let v = view {
                VStack(alignment: .leading, spacing: 16) {
                    if v.isCreator {
                        DLField(t("settings.name"), text: $name)
                        DLField(t("settings.welcomeMessage"), text: $welcome, multilineMinHeight: 140)
                        Button(busy ? t("common.saving") : t("common.save")) {
                            busy = true
                            Task {
                                do {
                                    view = try await backend.api.updateUniverse(name: name, welcome: welcome)
                                    backend.home.refreshSoon()
                                    notice(.text(t("settings.universeSaved")))
                                } catch let e as APIError {
                                    notice(.text((400 ..< 500).contains(e.status) ? e.message : t("common.notSavedTryAgain")))
                                } catch {}
                                busy = false
                            }
                        }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || (name == v.name && welcome == v.welcome))
                        DLSectionLabel(t("settings.entryKey"))
                        if let key = newKey {
                            Text(groupKey(key)).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(.dlInk).textSelection(.enabled)
                            HStack {
                                Button(t("universe.copy")) { UIPasteboard.general.string = groupKey(key); notice(.text(t("universe.copied"))) }.buttonStyle(DLButtonStyle(.tint))
                                ShareLink(item: groupKey(key)) { Label(t("universe.share"), systemImage: "square.and.arrow.up") }.buttonStyle(DLButtonStyle(.tint))
                            }
                        }
                        Text(v.codeRotatedAt.map { t("settings.keyMadeOn", ["day": DLTime.day($0)]) } ?? t("settings.keysCantBeShown"))
                            .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        Button(t("settings.makeANewKey")) { confirmKey = true }.buttonStyle(DLButtonStyle(.outline))
                    } else {
                        Text(t("settings.onlyCanChangeThis", ["username": v.creator?.username ?? t("settings.theCreator")])).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        DLSectionLabel(t("settings.name"))
                        Text(v.name).dlText(.body).foregroundStyle(.dlInk)
                        DLSectionLabel(t("settings.welcomeMessage"))
                        Text(v.welcome).dlText(.letterBody).foregroundStyle(.dlInk)
                        if let c = v.creator {
                            DLSectionLabel(t("settings.createdBy"))
                            Text(c.username).dlText(.body).foregroundStyle(.dlInk)
                        }
                    }
                }
                .padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle(t("settings.universe"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(t("settings.makeANewKey2"), isPresented: $confirmKey) {
            Button(t("settings.cancel"), role: .cancel) {}
            Button(t("settings.makeANewKey")) {
                Task {
                    if let k = try? await backend.api.rotateKey() {
                        newKey = k.code
                        view = try? await backend.api.universe()
                    } else {
                        notice(.text(t("settings.keyNotMade")))
                    }
                }
            }
        } message: {
            Text(t("settings.theOldKeyStopsWorking"))
        }
        .task {
            guard view == nil, let v = try? await backend.api.universe() else { return }
            view = v
            name = v.name
            welcome = v.welcome
        }
    }
}

/// Settings › Notifications: this device's permission, Pause all, and each section and event; the
/// choices follow the citizen to every device.
struct NotificationsScreen: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dlNotice) private var notice
    @Environment(\.openURL) private var openURL
    @State private var settings: NotifySettings?
    @State private var permission: UNAuthorizationStatusWord = .unknown

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("settings.thisDeviceNamed", ["device": deviceWord, "state": permission.word])).dlText(.subheadlineBold).foregroundStyle(.dlInk)
                        Text(permission.line).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    }
                    Spacer()
                    if permission != .on {
                        Button(permission == .blocked ? t("settings.settings") : t("settings.allow")) { allow() }.buttonStyle(DLButtonStyle(.tint))
                    }
                }
                .dlListRow()
            }
            if let s = settings {
                Section {
                    Toggle(isOn: Binding(get: { s.paused }, set: { change(paused: $0) })) {
                        DLRowLabel(t("settings.pauseAll"), subtitle: s.paused ? t("settings.pausedSub") : t("settings.pauseSub"))
                    }
                    .tint(.dlSeal)
                    .dlListRow()
                }
                ForEach(s.sections) { section in
                    Section {
                        Toggle(isOn: Binding(get: { section.enabled }, set: { change(values: [section.key: $0]) })) {
                            Text(section.key.capitalized).dlText(.callout).foregroundStyle(.dlInk)
                        }
                        .tint(.dlSeal)
                        .disabled(s.paused)
                        .dlListRow()
                        ForEach(section.events) { e in
                            Toggle(isOn: Binding(get: { e.enabled }, set: { change(values: [e.key: $0]) })) {
                                Text(eventWords(e.key)).dlText(.callout).foregroundStyle(.dlInk)
                            }
                            .tint(.dlSeal)
                            .disabled(s.paused || !section.enabled)
                            .padding(.leading, 12)
                            .dlListRow()
                        }
                    }
                }
                Section {
                    Text(t("settings.theseChoicesFollowYouTo"))
                        .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .dlGroupedList()
        .navigationTitle(t("settings.notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            permission = await UNAuthorizationStatusWord.current()
            settings = try? await backend.api.notifications()
        }
    }

    private func eventWords(_ key: String) -> String {
        key.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? key
    }

    private func change(paused: Bool? = nil, values: [String: Bool]? = nil) {
        Task {
            if let s = try? await backend.api.saveNotifications(paused: paused, values: values) {
                settings = s
            } else {
                notice(.text(t("common.couldntSave")))
            }
        }
    }

    private func allow() {
        if permission == .blocked {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            permission = await UNAuthorizationStatusWord.current()
            if permission == .on { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}

enum UNAuthorizationStatusWord {
    case unknown, on, off, blocked

    static func current() async -> UNAuthorizationStatusWord {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .on
        case .denied: .blocked
        default: .off
        }
    }

    var word: String {
        switch self {
        case .on: t("settings.device.on")
        case .blocked: t("settings.device.blocked")
        default: t("settings.device.off")
        }
    }

    private var device: String {
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    }

    var line: String {
        switch self {
        case .on: t("settings.device.onSubDevice", ["device": device])
        case .blocked: t("settings.device.blockedSubIos")
        default: t("settings.device.offSubDevice", ["device": device])
        }
    }
}

/// Change PIN: current, new, confirm (three steps on the pad).
struct ChangePinSheet: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var digits = ""
    @State private var current = ""
    @State private var new = ""
    @State private var error: String?
    @State private var busy = false
    @State private var done = false

    private let steps = [t("home.pinStep.current"), t("home.pinStep.new"), t("home.pinStep.confirm")]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(t("settings.changePin")).dlText(.title3).foregroundStyle(.dlInk)
                Spacer()
                DLGlassIconButton("xmark", label: t("universe.close")) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            if done {
                Spacer()
                Label(t("home.pinChanged"), systemImage: "checkmark.circle.fill").dlText(.headline).foregroundStyle(.dlInk)
                Spacer()
            } else {
                DLPinPanel(prompt: steps[step], hint: step == 0 ? t("home.yourOtherDevicesStayLogged") : nil,
                           error: error, digits: $digits, busy: busy, onComplete: complete) { EmptyView() }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.dlSheet)
    }

    private func complete(_ pin: String) {
        error = nil
        switch step {
        case 0:
            current = pin
            step = 1
            digits = ""
        case 1:
            new = pin
            step = 2
            digits = ""
        default:
            guard pin == new else {
                error = t("common.pinsDiffer")
                step = 1
                digits = ""
                return
            }
            busy = true
            Task {
                do {
                    try await backend.api.changePin(current: current, new: new)
                    if let me = backend.home.home?.me.id, backend.biometrics.isEnabled(userId: me) {
                        _ = backend.biometrics.store(pin: new, userId: me)
                    }
                    done = true
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                } catch let e as APIError {
                    error = e.code == "WRONG_PIN" ? t("common.wrongPin") : ((400 ..< 500).contains(e.status) ? e.message : t("settings.pinNotChanged"))
                    step = 0
                    digits = ""
                } catch {
                    self.error = t("settings.pinNotChanged")
                }
                busy = false
            }
        }
    }
}

/// X1: "Enter your PIN" before Face ID unlock is turned on; the PIN is checked by signing in again.
struct BiometricPinSheet: View {
    let userId: Int
    let onDone: (Bool) -> Void
    @Environment(Backend.self) private var backend
    @State private var digits = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        DLPinPanel(prompt: t("pin.enterYourPin"), hint: t("settings.bioKept", ["device": deviceWord, "bio": backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID"]),
                   error: error, digits: $digits, busy: busy, onComplete: { pin in
                       busy = true
                       Task {
                           do {
                               try await backend.api.login(userId: userId, pin: pin)
                               onDone(backend.biometrics.store(pin: pin, userId: userId))
                           } catch let e as APIError {
                               error = e.code == "WRONG_PIN" ? t("common.wrongPin") : t("pin.cantCheck")
                               digits = ""
                           } catch {}
                           busy = false
                       }
                   }) {
            Text(t("settings.bioUnlock", ["bio": backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID"])).dlText(.title3).foregroundStyle(.dlInk)
        }
        .padding(.top, 24)
        .presentationDetents([.large])
        .presentationBackground(.dlSheet)
    }
}
