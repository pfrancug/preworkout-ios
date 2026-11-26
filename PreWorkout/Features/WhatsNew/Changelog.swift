import Foundation

/// User-facing release notes bundled with the app (pl + en). Newest first.
/// One entry per App Store / TestFlight version (`MARKETING_VERSION`).
/// `highlight` items can appear in the "What's new" sheet after an update;
/// the rest only show in Profile › What's new. How to add one: docs/WHATS_NEW.md.
struct ChangelogEntry: Identifiable {
    let version: String
    /// YYYY-MM-DD release day; nil while unreleased.
    let date: String?
    let items: [ChangelogItem]
    var id: String { version }
}

struct ChangelogItem: Identifiable {
    let highlight: Bool
    let icon: String
    let pl: String
    let en: String
    var id: String { pl }

    var text: String { Changelog.usesPolish ? pl : en }

    static func big(_ icon: String, _ pl: String, _ en: String) -> ChangelogItem {
        ChangelogItem(highlight: true, icon: icon, pl: pl, en: en)
    }

    static func small(_ icon: String, _ pl: String, _ en: String) -> ChangelogItem {
        ChangelogItem(highlight: false, icon: icon, pl: pl, en: en)
    }
}

enum Changelog {
    /// Follows the per-app language (Settings › PreWorkout › Language).
    static var usesPolish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "pl").hasPrefix("pl")
    }

    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "0.1.6", date: nil, items: [
            .big("hourglass", "Nowy typ „Sesja”: blok czasu, np. 40 minut handstanda, z licznikiem prób i notatką",
                 "New Session type: a time block, e.g. 40 minutes of handstand, with an attempts counter and a note"),
            .big("timer", "Seria na czas zapisuje się sama po „Stop”, a przerwa startuje od razu",
                 "Timed sets save themselves when you tap Stop, and rest starts right away"),
            .big("clock", "Czas wszędzie jako minuty i sekundy (1:30, 1:05:00), ustawiany wygodnymi kółkami",
                 "Times everywhere as minutes and seconds (1:30, 1:05:00), set with easy wheels"),
            .big("arrow.uturn.backward", "Pominięte ćwiczenie przywrócisz jednym przyciskiem „Przywróć”",
                 "Bring a skipped exercise back with one Restore button"),
            .small("plus.circle", "„Jeszcze seria” dodaje kolejną serię zamiast zaczynać od pierwszej",
                   "\"One more set\" adds the next set instead of starting over from set 1"),
            .small("hand.tap", "Przyciski − / + nie otwierają już okna serii i nie reagują, gdy przesuwasz między ćwiczeniami",
                   "The − / + buttons no longer open the set sheet or fire while you swipe between exercises"),
            .small("rectangle.stack", "Wybór miejsca nowego ćwiczenia w czytelnym arkuszu, potwierdzenia na środku ekranu",
                   "Choosing where to add an exercise is a clear sheet; confirmations sit in the middle of the screen"),
            .small("clock.badge.checkmark", "Zegar treningu po godzinie mieści się w jednej linii, także na Dynamic Island",
                   "The workout clock stays on one line past one hour, also in the Dynamic Island"),
            .small("bolt.horizontal", "Aplikacja otwiera się od razu z danymi na telefonie i odświeża je w tle tylko, gdy coś się zmieniło",
                   "The app opens instantly from data on the phone and refreshes in the background only when something has changed"),
            .small("person.text.rectangle", "Opcjonalne nazwisko w profilu, a poziom aktywności i dane z kalkulatora zapisują się na koncie",
                   "Optional last name in your profile, and the activity level and calculator data are saved to your account"),
            .small("person.badge.key", "Nowy, czytelniejszy ekran logowania, od razu widać, co aplikacja daje",
                   "A clearer sign-in screen that shows what the app is for"),
            .small("sparkles", "Nowy ekran „Co nowego” w Profilu",
                   "New What's new screen in Profile"),
        ]),
        ChangelogEntry(version: "0.1.5", date: "2026-11-26", items: [
            .big("apple.logo", "Logowanie przez Apple i Twoje własne konto",
                 "Sign in with Apple and your own account"),
            .small("person.crop.circle.badge.xmark", "Wylogowanie i usuwanie konta w Ustawieniach",
                   "Sign out and delete your account in Settings"),
        ]),
        ChangelogEntry(version: "0.1.4", date: "2026-11-20", items: [
            .big("link", "Combo z osobną liczbą powtórzeń dla każdego ruchu, np. 1 / 5 / 1",
                 "Combos with separate reps for each movement, e.g. 1 / 5 / 1"),
            .small("target", "Usuwanie celu dziennego działa bez błędu, a cel bez kompletu makro pokazuje samo kcal",
                   "Deleting the daily goal works without an error, and a goal without all macros shows just kcal"),
            .small("questionmark.circle", "Kalkulator mówi, którego pola brakuje",
                   "The calculator tells you which field is missing"),
        ]),
        ChangelogEntry(version: "0.1.3", date: "2026-11-20", items: [
            .small("checkmark.shield", "Aplikacja nie zamyka się już po zapisaniu treningu na żywo",
                   "The app no longer closes after saving a live workout"),
        ]),
        ChangelogEntry(version: "0.1.2", date: "2026-11-20", items: [
            .big("square.stack.3d.up", "Wybierasz, z których zbiorów ćwiczeń korzystasz: Kalistenika, Siłownia, Własne",
                 "Pick which exercise sets you use: Calisthenics, Gym, Your own"),
            .small("flame", "Kalkulator kalorii zaczyna od pustych pól i pamięta dane na telefonie",
                   "The calorie calculator starts empty and remembers your data on the phone"),
            .small("checklist", "Prostszy wybór i wyłączanie planu kalorycznego",
                   "Simpler choosing and turning off of a calorie plan"),
        ]),
        ChangelogEntry(version: "0.1.1", date: "2026-11-20", items: [
            .big("figure.strengthtraining.traditional", "Nowy trening na żywo: duża liczba powtórzeń, jedna główna akcja i jasne „Teraz” oraz „Zrobione”",
                 "New live workout: big rep count, one main action and a clear Now vs Done"),
            .big("play.circle", "Osobna zakładka „Na żywo” z szybkim „Powtórz trening”",
                 "A dedicated Live tab with quick Repeat workout"),
        ]),
        ChangelogEntry(version: "0.1.0", date: "2026-11-19", items: [
            .big("iphone", "Pierwsza wersja na iPhone'a: treningi, ćwiczenia, kalorie i profil",
                 "First iPhone version: workouts, exercises, calories and profile"),
            .big("timer", "Trening na żywo z przerwą, superseriami i Live Activity na ekranie blokady",
                 "Live workouts with rest timer, supersets and a Lock Screen Live Activity"),
            .small("globe", "Polski i angielski; język zmienisz w ustawieniach iOS",
                   "Polish and English; change the language in iOS Settings"),
        ]),
    ]
}

/// "0.1.10" > "0.1.9": compares dot-separated numbers.
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func less(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}
