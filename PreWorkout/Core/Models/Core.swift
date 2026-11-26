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
    var lastName: String = ""
    var age: String
    var height: String
    /// "male" | "female" | ""
    var sex: String
    var avatarUrl: String?
    /// TDEE activity factor, or nil when not set.
    var activity: Double? = nil
    /// Current calculator weight (kg) as text, or empty.
    var weight: String = ""

    var displayName: String {
        let parts = [name, lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case name, lastName, age, height, sex, avatarUrl, activity, weight
    }

    init(name: String, lastName: String = "", age: String, height: String, sex: String, avatarUrl: String? = nil, activity: Double? = nil, weight: String = "") {
        self.name = name
        self.lastName = lastName
        self.age = age
        self.height = height
        self.sex = sex
        self.avatarUrl = avatarUrl
        self.activity = activity
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        age = Limits.cleanAge(try c.decodeIfPresent(String.self, forKey: .age) ?? "")
        height = Limits.cleanHeight(try c.decodeIfPresent(String.self, forKey: .height) ?? "")
        sex = try c.decodeIfPresent(String.self, forKey: .sex) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        activity = c.lenientDouble(.activity, NumericLimit(min: 1, max: 2))
        weight = Limits.cleanWeight(try c.decodeIfPresent(String.self, forKey: .weight) ?? "")
    }
}

struct Person: Decodable, Identifiable, Hashable {
    let id: String
    let isOwner: Bool
    let createdAt: String
    let name: String
    let lastName: String
    let age: String
    let height: String
    let sex: String
    let avatarUrl: String?
    let activity: Double?
    let weight: String

    var displayName: String {
        let parts = [name, lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return isOwner ? String(localized: "Ja") : id
    }

    private enum CodingKeys: String, CodingKey {
        case id, isOwner, createdAt, name, lastName, age, height, sex, avatarUrl, activity, weight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        age = Limits.cleanAge(try c.decodeIfPresent(String.self, forKey: .age) ?? "")
        height = Limits.cleanHeight(try c.decodeIfPresent(String.self, forKey: .height) ?? "")
        sex = try c.decodeIfPresent(String.self, forKey: .sex) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        activity = c.lenientDouble(.activity, NumericLimit(min: 1, max: 2))
        weight = Limits.cleanWeight(try c.decodeIfPresent(String.self, forKey: .weight) ?? "")
    }
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
