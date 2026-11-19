import Foundation

/// Localized names of the API's enum values (`shared/training.ts`, `shared/ai.ts`).
enum Labels {
    static let modalities = ["calisthenics", "gym", "cardio", "mobility", "other"]
    static let categories = ["push", "pull", "legs", "core", "skill", "mobility", "explosive"]
    static let difficulties = ["beginner", "intermediate", "advanced", "elite"]
    static let measurements = ["reps", "hold", "reps_weight", "distance_time"]
    static let assistance = ["none", "band", "partner", "other"]

    static func modality(_ value: String) -> LocalizedStringResource {
        switch value {
        case "calisthenics": return "Kalistenika"
        case "gym": return "Siłownia"
        case "cardio": return "Cardio"
        case "mobility": return "Mobilność"
        case "other": return "Inne"
        default: return LocalizedStringResource(stringLiteral: value)
        }
    }

    static func category(_ value: String) -> LocalizedStringResource {
        switch value {
        case "push": return "Pchanie"
        case "pull": return "Ciąganie"
        case "legs": return "Nogi"
        case "core": return "Core"
        case "skill": return "Umiejętności"
        case "mobility": return "Mobilność"
        case "explosive": return "Eksplozywne"
        default: return LocalizedStringResource(stringLiteral: value)
        }
    }

    static func difficulty(_ value: String) -> LocalizedStringResource {
        switch value {
        case "beginner": return "Początkujący"
        case "intermediate": return "Średniozaawansowany"
        case "advanced": return "Zaawansowany"
        case "elite": return "Elita"
        default: return LocalizedStringResource(stringLiteral: value)
        }
    }

    static func measurement(_ value: String) -> LocalizedStringResource {
        switch value {
        case "reps": return "Powtórzenia"
        case "hold": return "Czas utrzymania"
        case "reps_weight": return "Powtórzenia + ciężar"
        case "distance_time": return "Dystans / czas"
        default: return LocalizedStringResource(stringLiteral: value)
        }
    }

    static func assistance(_ value: String) -> LocalizedStringResource {
        switch value {
        case "none": return "Bez asysty"
        case "band": return "Guma"
        case "partner": return "Partner"
        case "other": return "Inna asysta"
        default: return LocalizedStringResource(stringLiteral: value)
        }
    }

    static func sex(_ value: String) -> LocalizedStringResource {
        switch value {
        case "male": return "Mężczyzna"
        case "female": return "Kobieta"
        default: return "Nie podano"
        }
    }
}
