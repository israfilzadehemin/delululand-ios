import DLData
import DLI18n
import DLNetwork
import DLUI
import Foundation
import Observation

/// Doc "Delululand — Universe" U5, U7, U9 (web `src/api/universe.ts`, `src/profile/rules.ts`).
public enum StartRules {
    public static let welcomeMax = 1500

    public static func nameOK(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return (2...12).contains(trimmed.count) && trimmed.unicodeScalars.allSatisfy { CharacterSet.letters.union(.decimalDigits).contains($0) }
    }

    public static func usernameOK(_ name: String) -> Bool {
        (3...16).contains(name.count) && name.unicodeScalars.allSatisfy { CharacterSet.letters.union(.decimalDigits).contains($0) }
    }

    public static func usernameTaken(_ name: String, taken: [String]) -> Bool {
        taken.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func welcomeLength(_ welcome: String) -> Int {
        welcome.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    /// U5: the three paragraphs with the universe's name in place of "Delulutopia".
    public static func welcomeTemplate(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let n = trimmed.isEmpty ? t("universe.yourUniverse") : trimmed
        return [t("universe.welcome.p1", ["name": n]), t("universe.welcome.p2", ["name": n]), t("universe.welcome.p3")].joined(separator: "\n\n")
    }

    public static func paragraphs(_ welcome: String) -> [String] {
        welcome.components(separatedBy: "\n")
            .split { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// S0 without a session (Universe §2.1): the landing with the key field while this device has no
/// entry pass (UV-1, UV-2), else that universe's cards plus "Join" while it has room and "Use a
/// different key" (UV-4). A correct key first shows the welcome (UV-3).
@MainActor
@Observable
final class EntryModel {
    enum Content: Equatable {
        case loading
        case landing
        case cards(EntryView)
        case unreachable
    }

    var content: Content = .loading
    var key = ""
    var wrong = false
    var offline = false
    var busy = false
    var welcome: Entered?

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func load() async {
        do {
            content = .cards(try await backend.api.entry())
        } catch let error as APIError {
            content = error.code == "ENTRY_REQUIRED" ? .landing : .unreachable
        } catch {
            content = .unreachable
        }
    }

    func setKey(_ raw: String) {
        key = groupKey(raw)
        wrong = false
        offline = false
    }

    func submit() async {
        guard !busy, !key.isEmpty else { return }
        busy = true
        wrong = false
        offline = false
        defer { busy = false }
        do {
            let code = key
            let entered = try await backend.retryingThrottle("CODE_THROTTLED") { try await backend.api.enter(code: code) }
            if !entered.welcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { welcome = entered }
            await load()
        } catch let error as APIError {
            wrong = error.code == "WRONG_CODE" || error.code == "CODE_THROTTLED"
            offline = !wrong
        } catch {
            offline = true
        }
    }

    /// "Use a different key": this device forgets its universe.
    func forget() async {
        content = .loading
        try? await backend.api.forgetEntry()
        key = ""
        await load()
    }
}

/// S1 PIN (FS-A3–A8): enter, or on first login create then confirm (the compare is here; the API
/// receives the PIN once). Nothing typed outlives an attempt. Success refreshes the session.
@MainActor
@Observable
final class PinModel {
    enum Mode { case enter, create, confirm }

    enum Problem: Equatable {
        case wrong, differ, offline
        case text(String)
    }

    let userId: Int
    var user: UserCard?
    var index = 0
    var universe = ""
    var mode: Mode = .enter
    var digits = ""
    var problem: Problem?
    var busy = false
    /// No entry pass any more, or not a citizen here: back to the start.
    var leave = false

    private var first = ""
    private let backend: Backend

    init(userId: Int, backend: Backend) {
        self.userId = userId
        self.backend = backend
    }

    var canUseBiometrics: Bool {
        mode == .enter && user != nil && backend.biometrics.isAvailable && backend.biometrics.hasPin(userId: userId)
    }

    func load() async {
        do {
            let view = try await backend.api.entry()
            guard let i = view.users.firstIndex(where: { $0.id == userId }) else {
                leave = true
                return
            }
            user = view.users[i]
            index = i
            universe = view.name
            mode = view.users[i].hasPin ? .enter : .create
        } catch let error as APIError {
            if error.code == "ENTRY_REQUIRED" { leave = true } else { problem = .offline }
        } catch {
            problem = .offline
        }
    }

    func typed(_ d: String) {
        if !d.isEmpty { problem = nil }
    }

    func complete(_ pin: String) {
        guard !busy else { return }
        switch mode {
        case .create:
            first = pin
            mode = .confirm
            digits = ""
            problem = nil
        case .confirm:
            if pin != first {
                fail(.differ, mode: .create)
            } else {
                Task { await submit(pin, fromBiometrics: false) }
            }
        case .enter:
            Task { await submit(pin, fromBiometrics: false) }
        }
    }

    /// The PIN kept behind Face ID, sent as if typed; a refused one is forgotten.
    func unlockWithBiometrics() async {
        guard mode == .enter, !busy else { return }
        let reason = t("pin.unlockBrand", ["brand": universe.isEmpty ? "Delulutopia" : universe])
        guard let pin = await backend.biometrics.pin(userId: userId, reason: reason) else { return }
        await submit(pin, fromBiometrics: true)
    }

    private func submit(_ pin: String, fromBiometrics: Bool) async {
        let current = mode
        busy = true
        problem = nil
        do {
            let id = userId
            if current == .enter {
                try await backend.retryingThrottle("PIN_THROTTLED") { try await backend.api.login(userId: id, pin: pin) }
            } else {
                try await backend.retryingThrottle("PIN_THROTTLED") { try await backend.api.createPin(userId: id, pin: pin) }
            }
            if !fromBiometrics {
                backend.pendingBiometricOffer = PendingBiometricOffer(userId: userId, pin: pin)
            }
            await backend.session.refresh()
            busy = false
            digits = ""
        } catch let error as APIError {
            switch error.code {
            case "ENTRY_REQUIRED":
                leave = true
            case "NO_PIN":
                fail(nil, mode: .create)
            case "PIN_EXISTS":
                fail(nil, mode: .enter)
            case "WRONG_PIN", "PIN_THROTTLED", "BAD_PIN":
                if current == .enter {
                    // Changed on another device since: the kept PIN is stale.
                    if fromBiometrics { backend.biometrics.remove(userId: userId) }
                    fail(.wrong, mode: .enter)
                } else {
                    fail(.text(error.message), mode: .create)
                }
            default:
                if error.isOffline {
                    fail(.offline, mode: current == .enter ? .enter : .create)
                } else {
                    fail(.text(error.message), mode: current == .enter ? .enter : .create)
                }
            }
        } catch {
            fail(.offline, mode: current == .enter ? .enter : .create)
        }
    }

    private func fail(_ problem: Problem?, mode: Mode) {
        if mode == .create { first = "" }
        self.problem = problem
        self.mode = mode
        digits = ""
        busy = false
    }
}

/// C4 and J2: "Create your PIN" then "Confirm your PIN". The sixth confirm digit submits; a refusal
/// starts the PIN over with its text.
struct WizardPin: Equatable {
    var confirming = false
    var first = ""
    var digits = ""
    var problem: PinModel.Problem?
    var busy = false

    /// The PIN to submit once both entries match, else nil.
    mutating func complete(_ pin: String) -> String? {
        if !confirming {
            self = WizardPin(confirming: true, first: pin)
            return nil
        }
        if pin != first {
            self = WizardPin(problem: .differ)
            return nil
        }
        busy = true
        problem = nil
        return pin
    }

    mutating func restart(_ problem: PinModel.Problem?) {
        self = WizardPin(problem: problem)
    }
}

/// C3 and J1: what a citizen needs to exist, and an optional photo (U9), uploaded once they are in.
struct CitizenDraft: Equatable {
    var username = ""
    var timezone = Zones.device
    var photo: Data?
}

/// U9: the photo goes up once the citizen exists; a failure is said later (Profile can add it).
@MainActor
func uploadPhoto(_ photo: Data?, backend: Backend) async {
    guard let photo else { return }
    _ = try? await backend.api.uploadAvatar(jpeg: photo)
}

/// Create a universe (Universe §2.2, C1–C5): invite → name and welcome → citizen → PIN; the sixth
/// confirm digit creates everything at once, then the key is shown once. Nothing is stored before
/// the PIN step, so leaving earlier keeps the invite unused.
@MainActor
@Observable
final class CreateUniverseModel {
    enum InviteProblem { case wrong, offline }

    var step = 1
    var invite = ""
    var inviteProblem: InviteProblem?
    var name = ""
    var nameServerError: String?
    var welcome = StartRules.welcomeTemplate("")
    var welcomeEdited = false
    var preview = false
    var citizen = CitizenDraft()
    var citizenError: String?
    var pin = WizardPin()
    var busy = false
    var created: (code: String, name: String)?

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func setInvite(_ raw: String) {
        invite = groupKey(raw)
        inviteProblem = nil
    }

    func checkInvite() async {
        guard !busy, !invite.isEmpty else { return }
        busy = true
        inviteProblem = nil
        defer { busy = false }
        do {
            try await backend.api.checkInvite(invite)
            step = 2
        } catch let error as APIError {
            inviteProblem = error.isOffline ? .offline : .wrong
        } catch {
            inviteProblem = .offline
        }
    }

    /// C2: while untouched, the welcome follows the name as it is typed.
    func setName(_ raw: String) {
        name = String(raw.filter { !$0.isWhitespace }.prefix(24))
        nameServerError = nil
        if !welcomeEdited { welcome = StartRules.welcomeTemplate(name) }
    }

    func setWelcome(_ text: String) {
        guard text != welcome else { return }
        welcome = text
        welcomeEdited = true
    }

    func resetWelcome() {
        welcome = StartRules.welcomeTemplate(name)
        welcomeEdited = false
    }

    var welcomeError: String? {
        if welcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t("universe.writeAFewWords") }
        if StartRules.welcomeLength(welcome) > StartRules.welcomeMax { return t("universe.welcomeMax") }
        return nil
    }

    func next() {
        step = min(step + 1, 4)
    }

    /// Back on steps 2–4 goes one step back; on step 1 the flow leaves.
    func back() -> Bool {
        guard (2...4).contains(step) else { return false }
        step -= 1
        pin = WizardPin()
        return true
    }

    func pinComplete(_ entered: String) {
        guard let value = pin.complete(entered) else { return }
        Task { await create(value) }
    }

    private func create(_ pinValue: String) async {
        do {
            let request = CreateUniverseRequest(
                invite: invite, name: name.trimmingCharacters(in: .whitespaces), welcome: welcome,
                username: citizen.username, timezone: citizen.timezone, pin: pinValue
            )
            let result = try await backend.api.createUniverse(request)
            await uploadPhoto(citizen.photo, backend: backend)
            created = (result.code, result.universe.name)
            pin = WizardPin()
            step = 5
        } catch let error as APIError {
            if error.isOffline {
                pin.restart(.offline)
            } else {
                switch error.code {
                case "INVITE_INVALID", "INVITE_THROTTLED":
                    step = 1
                    inviteProblem = .wrong
                    pin = WizardPin()
                case "UNIVERSE_NAME_INVALID", "WELCOME_INVALID":
                    step = 2
                    nameServerError = error.code == "UNIVERSE_NAME_INVALID" ? error.message : nil
                    pin = WizardPin()
                case "USERNAME_INVALID", "TIMEZONE_INVALID":
                    step = 3
                    citizenError = error.message
                    pin = WizardPin()
                default:
                    pin.restart(.text(error.message))
                }
            }
        } catch {
            pin.restart(.offline)
        }
    }

    /// After the key: the new session opens Home.
    func finish() async {
        await backend.session.refresh()
    }
}

/// Join (Universe §2.3, J1–J2): needs the universe's entry pass. The username is checked at once
/// against the citizen already there, and again by the server; a universe that filled up meanwhile
/// sends the person back to its cards.
@MainActor
@Observable
final class JoinModel {
    var loaded = false
    var name = ""
    var taken: [String] = []
    var step = 1
    var citizen = CitizenDraft()
    var serverError: String?
    var pin = WizardPin()
    var leave = false

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func load() async {
        do {
            let view = try await backend.api.entry()
            if !view.canJoin {
                leave = true
            } else {
                name = view.name
                taken = view.users.map(\.nickname)
            }
            loaded = true
        } catch let error as APIError {
            leave = error.code == "ENTRY_REQUIRED" || !error.isOffline
            loaded = true
        } catch {
            loaded = true
        }
    }

    func back() -> Bool {
        guard step == 2 else { return false }
        step = 1
        pin = WizardPin()
        return true
    }

    func pinComplete(_ entered: String) {
        guard let value = pin.complete(entered) else { return }
        Task { await join(value) }
    }

    private func join(_ pinValue: String) async {
        do {
            try await backend.api.join(username: citizen.username, timezone: citizen.timezone, pin: pinValue)
            await uploadPhoto(citizen.photo, backend: backend)
            await backend.session.refresh()
        } catch let error as APIError {
            if error.isOffline {
                pin.restart(.offline)
            } else if error.code == "UNIVERSE_FULL" || error.code == "ENTRY_REQUIRED" {
                leave = true
            } else if ["USERNAME_TAKEN", "USERNAME_INVALID", "TIMEZONE_INVALID"].contains(error.code) {
                step = 1
                serverError = error.message
                pin = WizardPin()
            } else {
                pin.restart(.text(error.message))
            }
        } catch {
            pin.restart(.offline)
        }
    }
}
