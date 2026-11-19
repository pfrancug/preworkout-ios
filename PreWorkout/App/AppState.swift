import Foundation
import Observation

/// Global app state: sign-in status, people and the active person.
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
    private(set) var people: [Person] = []
    /// AI endpoints are only available when the server says so (`GET /api/health`).
    private(set) var aiEnabled = false

    var activePersonId: String {
        didSet { UserDefaults.standard.set(activePersonId, forKey: Self.activePersonKey) }
    }

    var activePerson: Person? { people.first { $0.id == activePersonId } }

    private static let activePersonKey = "preworkout.activePersonId"
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        activePersonId = UserDefaults.standard.string(forKey: Self.activePersonKey) ?? Person.ownerId
        NotificationCenter.default.addObserver(
            forName: .apiUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.phase = .needsLogin }
        }
    }

    func bootstrap() async {
        phase = .checking
        guard ServerConfig.baseURL != nil else {
            phase = .needsLogin
            return
        }
        do {
            let health = try await api.health()
            aiEnabled = health.ai
            let session = try await api.authSession()
            if session.required && !session.authenticated {
                phase = .needsLogin
                return
            }
            try await loadPeople()
            phase = .ready
        } catch {
            phase = .offline(error.localizedDescription)
        }
    }

    func login(password: String) async throws {
        try await api.login(password: password)
        try await loadPeople()
        phase = .ready
    }

    func logout() async {
        try? await api.logout()
        phase = .needsLogin
    }

    /// Activity categories of the active person (workout category picker).
    private(set) var categories: [ActivityCategory] = []
    private var categoriesPersonId: String?

    func loadCategoriesIfNeeded() async {
        guard categoriesPersonId != activePersonId else { return }
        let personId = activePersonId
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
            activePersonId = Person.ownerId
        }
    }
}
