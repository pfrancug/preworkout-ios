import Foundation

// Shapes mirror `shared/types.ts` of the web app (JSON is camelCase).

struct Health: Decodable {
    let ok: Bool
    let ai: Bool
}

struct Account: Decodable, Equatable {
    let id: String
    let name: String
    let email: String?
    let appleLinked: Bool
    let isAdmin: Bool
}

struct AuthMethods: Decodable, Equatable {
    let apple: Bool
    let password: Bool
}

struct AuthSession: Decodable {
    let required: Bool
    let authenticated: Bool
    let user: Account?
    let methods: AuthMethods?
}

struct AppleAuthResponse: Decodable {
    let token: String
    let expiresAt: String
    let user: Account
}

struct UserSettings: Codable, Equatable {
    var name: String
    var age: String
    var height: String
    /// "male" | "female" | ""
    var sex: String
    var avatarUrl: String?
}

struct Person: Decodable, Identifiable, Hashable {
    let id: String
    let isOwner: Bool
    let createdAt: String
    let name: String
    let age: String
    let height: String
    let sex: String
    let avatarUrl: String?

    var displayName: String { name.isEmpty ? (isOwner ? String(localized: "Ja") : id) : name }
}

struct UserPreferences: Decodable {
    let language: String?
    /// xai | local (global AI provider preference)
    let aiProvider: String?
}

struct ActivityCategory: Codable, Identifiable, Hashable {
    let id: String
    var icon: String
    var name: String
    var color: String
    var archived: Bool?
}
