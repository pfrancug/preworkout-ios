import SwiftUI

/// Tab: the active person's profile card (opens the editor), person switch, app settings and info.
struct ProfileView: View {
    @State private var whatsNew = WhatsNewStore.shared
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<UserSettings> = .idle

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                switch state {
                case .idle, .loading:
                    Section { ProgressView().frame(maxWidth: .infinity) }
                case .failed(let message):
                    Section {
                        ErrorText(message: message)
                        Button("Spróbuj ponownie") { Task { await load() } }
                    }
                case .loaded(let settings):
                    profileCard(settings)
                }

                if appState.people.count > 1 {
                    Section {
                        Picker(selection: $appState.activePersonId) {
                            ForEach(appState.people) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        } label: {
                            IconLabel("Osoba", icon: "person.2")
                        }
                    } footer: {
                        Text("Treningi, profil i cel dotyczą wybranej osoby.")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        IconRow("Ustawienia", icon: "gearshape")
                    }
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        IconRow("Co nowego", icon: "sparkles", badge: whatsNew.hasUnseen)
                    }
                } header: {
                    Text("Aplikacja")
                }

                Section {
                    if let privacy = URL(string: "https://preworkout.fit/privacy") {
                        Link(destination: privacy) {
                            IconRow("Polityka prywatności", icon: "hand.raised", external: true)
                        }
                    }
                    if let support = URL(string: "https://preworkout.fit/support") {
                        Link(destination: support) {
                            IconRow("Wsparcie", icon: "questionmark.circle", external: true)
                        }
                    }
                } header: {
                    Text("Informacje")
                }
            }
            .navigationTitle("Profil")
            .refreshable { await load() }
            .sensoryFeedback(.selection, trigger: appState.activePersonId)
        }
        .appNavigationChrome()
        .keepsTabBarVisible("profile")
        .task {
            if state.isIdle { await load() }
        }
    }

    private func profileCard(_ settings: UserSettings) -> some View {
        Section {
            NavigationLink {
                EditProfileView(settings: settings) { updated in
                    state = .loaded(updated)
                }
            } label: {
                HStack(spacing: 16) {
                    AvatarView(url: settings.avatarUrl, name: displayName(settings))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName(settings))
                            .font(.title2.bold())
                        if let summary = ProfileSummary.text(settings) {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityHint(Text("Edytuj profil"))
        }
    }

    private func displayName(_ settings: UserSettings) -> String {
        let name = settings.displayName
        if !name.isEmpty { return name }
        return appState.activePerson?.displayName ?? String(localized: "Ja")
    }

    private func load() async {
        let person = appState.activePersonId
        if state.value == nil, let cached: UserSettings = DiskCache.read("settings", person: person) {
            state = .loaded(cached)
        }
        do {
            state = .loaded(try await APIClient.shared.settings(person: person))
        } catch {
            guard !Task.isCancelled else { return }
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }
}

enum ProfileSummary {
    /// "Mężczyzna · 30 lat · 180 cm", nil when nothing is set.
    static func text(_ s: UserSettings) -> String? {
        var parts: [String] = []
        if s.sex == "male" || s.sex == "female" { parts.append(String(localized: Labels.sex(s.sex))) }
        if let age = s.effectiveAge { parts.append(String(localized: "\(age) lat")) }
        if let height = Int(s.height), height > 0 { parts.append("\(height) cm") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
