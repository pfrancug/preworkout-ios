import Foundation
import Observation

/// Global app state: sign-in status, account, people and the active person.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case checking
        case needsLogin
        case ready
        case offline(String)
    }

    private(set) var phase: Phase = .checking
    private(set) var account: Account?
    private(set) var people: [Person] = []
    /// AI endpoints are only available when the server says so (`GET /api/health`).
    private(set) var aiEnabled = false
    /// Incremented after account deletion so stores drop local preferences too.
    private(set) var accountDeletedCount = 0

    var activePersonId: String {
        didSet {
            if activePersonId.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.activePersonKey)
            } else {
                UserDefaults.standard.set(activePersonId, forKey: Self.activePersonKey)
            }
        }
    }

    var activePerson: Person? { people.first { $0.id == activePersonId } }

    private static let activePersonKey = "preworkout.activePersonId"
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        activePersonId = UserDefaults.standard.string(forKey: Self.activePersonKey) ?? ""
        NotificationCenter.default.addObserver(
            forName: .apiUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                KeychainToken.clear()
                self?.account = nil
                self?.phase = .needsLogin
            }
        }
    }

    func bootstrap() async {
        guard ServerConfig.baseURL != nil else {
            phase = .needsLogin
            return
        }
        if hydrateFromCache() {
            phase = .ready
            Task { await refreshFromNetwork(showErrors: false) }
            return
        }
        phase = .checking
        await refreshFromNetwork(showErrors: true)
    }

    /// Instant launch: cached session + people for the last signed-in user.
    @discardableResult
    private func hydrateFromCache() -> Bool {
        guard KeychainToken.get() != nil,
              let userId = DiskCache.currentUserId(),
              let session: AuthSession = DiskCache.read(.init(userId: userId, personId: nil, name: "session")),
              session.authenticated,
              let cachedPeople: [Person] = DiskCache.read(.init(userId: userId, personId: nil, name: "people"))
        else { return false }
        account = session.user
        people = cachedPeople
        if !people.contains(where: { $0.id == activePersonId }) {
            activePersonId = people.first(where: \.isOwner)?.id ?? people.first?.id ?? ""
        }
        return true
    }

    private func refreshFromNetwork(showErrors: Bool) async {
        do {
            let health = try await api.health()
            aiEnabled = health.ai
            let session = try await api.authSession()
            if session.required && !session.authenticated {
                KeychainToken.clear()
                DiskCache.clearAll()
                account = nil
                people = []
                phase = .needsLogin
                return
            }
            if let user = session.user { DiskCache.setCurrentUser(user.id) }
            Outbox.shared.flush()
            account = session.user
            try await loadPeople()
            phase = .ready
        } catch {
            if showErrors && phase != .ready {
                phase = .offline(error.localizedDescription)
            }
        }
    }

    func signInWithApple(_ payload: AppleCredentialPayload) async throws {
        let response = try await api.appleNative(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode,
            nonce: payload.nonce,
            fullName: payload.fullName,
            link: false
        )
        DiskCache.clearAll()
        KeychainToken.set(response.token)
        api.clearSessionCookies()
        DiskCache.setCurrentUser(response.user.id)
        Outbox.shared.flush()
        account = response.user
        activePersonId = ""
        categories = []
        categoriesPersonId = nil
        try await loadPeople()
        phase = .ready
    }

    func linkApple(_ payload: AppleCredentialPayload) async throws {
        let response = try await api.appleNative(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode,
            nonce: payload.nonce,
            fullName: payload.fullName,
            link: true
        )
        KeychainToken.set(response.token)
        api.clearSessionCookies()
        account = response.user
        try? await loadPeople()
    }

    func logout() async {
        try? await api.logout()
        clearLocalSession(wipeUserDefaults: false)
        phase = .needsLogin
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        clearLocalSession(wipeUserDefaults: true)
        accountDeletedCount += 1
        phase = .needsLogin
    }

    private func clearLocalSession(wipeUserDefaults: Bool) {
        KeychainToken.clear()
        api.clearSessionCookies()
        account = nil
        people = []
        categories = []
        categoriesPersonId = nil
        activePersonId = ""
        DiskCache.clearAll()
        if wipeUserDefaults {
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            LiveStore.deleteAllLocalSessions()
            Outbox.shared.discardAll()
        }
    }

    /// Activity categories of the active person (workout category picker).
    private(set) var categories: [ActivityCategory] = []
    private var categoriesPersonId: String?

    func loadCategoriesIfNeeded() async {
        guard !activePersonId.isEmpty else { return }
        let personId = activePersonId
        if categoriesPersonId != personId, let cached: [ActivityCategory] = DiskCache.read("categories", person: personId) {
            categories = cached
            categoriesPersonId = personId
        }
        if let list = try? await api.categories(person: personId) {
            categories = list
            categoriesPersonId = personId
        }
    }

    func category(_ id: String?) -> ActivityCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func loadPeople() async throws {
        people = try await api.people()
        if !people.contains(where: { $0.id == activePersonId }) {
            activePersonId = people.first(where: \.isOwner)?.id ?? people.first?.id ?? ""
        }
    }
}
