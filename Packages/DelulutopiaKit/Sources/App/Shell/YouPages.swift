import DLData
import DLDesignSystem
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
        let friend = backend.home.home?.friend?.nickname ?? "your friend"
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        DLRemoteAvatar(url: profile.avatarUrl, name: profile.username, size: 72, signature: .a, ring: true)
                            .overlay { if photoBusy { ProgressView() } }
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Change photo", systemImage: "camera") { choosing = true }
                                .buttonStyle(DLButtonStyle(.tint))
                            if profile.avatarUrl != nil {
                                Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                                    .foregroundStyle(.dlError)
                            }
                        }
                        .disabled(photoBusy)
                    }
                    DLField("Username", text: $username)
                    DLField("Name", text: $first)
                    DLField("Surname", text: $last)
                    DLTimeZoneField(zone: zone) { zone = $0 }
                    Text("Your username is what \(friend) sees everywhere. Name and surname show only on your profiles. Your time zone sets your clock on Home.")
                        .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError) }
                    Button(busy ? "Saving…" : "Save") { save() }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Color.dlPaper.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .dlPhotoChooser(isPresented: $choosing, hasPhoto: profile?.avatarUrl != nil, onPhoto: upload) { confirmRemove = true }
        .confirmationDialog("Remove your photo?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    photoBusy = true
                    if let p = try? await backend.api.removeAvatar() { profile = p; backend.home.refreshSoon() }
                    photoBusy = false
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: { Text("Your initials show instead, for you and for \(friend).") }
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
                notice(.text(e.isOffline ? "Upload failed. Try again." : e.message))
            } catch {
                notice(.text("Upload failed. Try again."))
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
                notice(.text("Profile saved"))
            } catch let e as APIError where (400 ..< 500).contains(e.status) {
                error = e.message
            } catch {
                self.error = "Not saved. Try again."
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
                            Text(full.isEmpty ? "No name added" : full).dlText(.subheadline).foregroundStyle(.dlInkQuiet)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        if let tz = f.timezone {
                            let t = DLTime.wallClock(now, zone: tz)
                            fact("Local time", String(format: "%02d:%02d", t.hour, t.minute) + " · " + DLTime.city(of: tz))
                        }
                        fact("Mood", f.moodText.map { "\($0) · \(ageWords(f.moodSetAt, now: now))" } ?? "No mood yet")
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
                        DLField("Name", text: $name)
                        DLField("Welcome message", text: $welcome, multilineMinHeight: 140)
                        Button(busy ? "Saving…" : "Save") {
                            busy = true
                            Task {
                                do {
                                    view = try await backend.api.updateUniverse(name: name, welcome: welcome)
                                    backend.home.refreshSoon()
                                    notice(.text("Saved"))
                                } catch let e as APIError {
                                    notice(.text((400 ..< 500).contains(e.status) ? e.message : "Not saved. Try again."))
                                } catch {}
                                busy = false
                            }
                        }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || (name == v.name && welcome == v.welcome))
                        DLSectionLabel("Entry key")
                        if let key = newKey {
                            Text(groupKey(key)).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(.dlInk).textSelection(.enabled)
                            HStack {
                                Button("Copy") { UIPasteboard.general.string = groupKey(key); notice(.text("Copied")) }.buttonStyle(DLButtonStyle(.tint))
                                ShareLink(item: groupKey(key)) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(DLButtonStyle(.tint))
                            }
                        }
                        Text("\(v.codeRotatedAt.map { "Made \(DLTime.day($0)). " } ?? "")Keys can’t be shown again; make a new one if it’s lost.")
                            .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        Button("Make a new key") { confirmKey = true }.buttonStyle(DLButtonStyle(.outline))
                    } else {
                        Text("Only \(v.creator?.username ?? "the creator") can change this.").dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        DLSectionLabel("Name")
                        Text(v.name).dlText(.body).foregroundStyle(.dlInk)
                        DLSectionLabel("Welcome message")
                        Text(v.welcome).dlText(.letterBody).foregroundStyle(.dlInk)
                        if let c = v.creator {
                            DLSectionLabel("Created by")
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
        .navigationTitle("Universe")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Make a new key?", isPresented: $confirmKey) {
            Button("Cancel", role: .cancel) {}
            Button("Make a new key") {
                Task {
                    if let k = try? await backend.api.rotateKey() {
                        newKey = k.code
                        view = try? await backend.api.universe()
                    } else {
                        notice(.text("Not made. Try again."))
                    }
                }
            }
        } message: {
            Text("The old key stops working. Devices that are logged in stay in; devices that only entered the key will need the new one.")
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
                        Text("This \(deviceWord) · \(permission.word)").dlText(.subheadlineBold).foregroundStyle(.dlInk)
                        Text(permission.line).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                    }
                    Spacer()
                    if permission != .on {
                        Button(permission == .blocked ? "Settings" : "Allow") { allow() }.buttonStyle(DLButtonStyle(.tint))
                    }
                }
                .dlListRow()
            }
            if let s = settings {
                Section {
                    Toggle(isOn: Binding(get: { s.paused }, set: { change(paused: $0) })) {
                        DLRowLabel("Pause all", subtitle: s.paused ? "Nothing is pushed to any of your devices" : "Stop every push on all your devices")
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
                    Text("These choices follow you to every device. Dots and NEW marks inside the app stay as they are.")
                        .dlText(.footnote).foregroundStyle(.dlInkQuiet)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .dlGroupedList()
        .navigationTitle("Notifications")
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
                notice(.text("Couldn’t save. Try again."))
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
        case .on: "On"
        case .blocked: "Blocked"
        default: "Off"
        }
    }

    var line: String {
        switch self {
        case .on: "Notifications reach this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")."
        case .blocked: "Notifications are off for Delulutopia in iOS Settings."
        default: "This \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") won’t show notifications."
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

    private let steps = ["Current PIN", "New PIN", "Confirm new PIN"]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Change PIN").dlText(.title3).foregroundStyle(.dlInk)
                Spacer()
                DLGlassIconButton("xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            if done {
                Spacer()
                Label("PIN changed", systemImage: "checkmark.circle.fill").dlText(.headline).foregroundStyle(.dlInk)
                Spacer()
            } else {
                DLPinPanel(prompt: steps[step], hint: step == 0 ? "Your other devices stay logged in. Forgot the current one? It can be cleared on the server; there is no e-mail reset." : nil,
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
                error = "PINs differ. Start again."
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
                    error = e.code == "WRONG_PIN" ? "Wrong PIN. Try again." : ((400 ..< 500).contains(e.status) ? e.message : "Not changed. Try again.")
                    step = 0
                    digits = ""
                } catch {
                    self.error = "Not changed. Try again."
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
        DLPinPanel(prompt: "Enter your PIN", hint: "Kept on this \(deviceWord) only, opened by \(backend.biometrics.kind == .touchID ? "Touch ID" : "Face ID").",
                   error: error, digits: $digits, busy: busy, onComplete: { pin in
                       busy = true
                       Task {
                           do {
                               try await backend.api.login(userId: userId, pin: pin)
                               onDone(backend.biometrics.store(pin: pin, userId: userId))
                           } catch let e as APIError {
                               error = e.code == "WRONG_PIN" ? "Wrong PIN. Try again." : "Can’t check your PIN. Try again."
                               digits = ""
                           } catch {}
                           busy = false
                       }
                   }) {
            Text(backend.biometrics.kind == .touchID ? "Touch ID unlock" : "Face ID unlock").dlText(.title3).foregroundStyle(.dlInk)
        }
        .padding(.top, 24)
        .presentationDetents([.large])
        .presentationBackground(.dlSheet)
    }
}
