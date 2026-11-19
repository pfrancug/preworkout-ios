import SwiftUI
import UIKit

/// Tab: person switcher, profile of the active person, app info, sign out.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<UserSettings> = .idle
    @State private var form = UserSettings(name: "", age: "", height: "", sex: "", avatarUrl: nil)
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0
    @State private var confirmLogout = false

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                if appState.people.count > 1 {
                    Section {
                        Picker("Osoba", selection: $appState.activePersonId) {
                            ForEach(appState.people) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                    } footer: {
                        Text("Treningi i profil dotyczą wybranej osoby.")
                    }
                }

                profileSection

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        LabeledContent("Język") {
                            Text(currentLanguage).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    LabeledContent("Serwer", value: ServerConfig.baseURL?.host() ?? "–")
                    LabeledContent("Wersja", value: version)
                } header: {
                    Text("Aplikacja")
                } footer: {
                    Text("Język zmienisz w Ustawieniach iOS › PreWorkout › Język.")
                }

                Section {
                    Button("Wyloguj", role: .destructive) { confirmLogout = true }
                }
            }
            .navigationTitle("Profil")
            .refreshable { await load() }
            .confirmationDialog("Wylogować się?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Wyloguj", role: .destructive) { Task { await appState.logout() } }
            }
            .sensoryFeedback(.success, trigger: saved)
            .sensoryFeedback(.selection, trigger: appState.activePersonId)
        }
        .task {
            if state.isIdle { await load() }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        switch state {
        case .idle, .loading:
            Section { ProgressView().frame(maxWidth: .infinity) }
        case .failed(let message):
            Section {
                ErrorText(message: message)
                Button("Spróbuj ponownie") { Task { await load() } }
            }
        case .loaded(let original):
            Section {
                TextField("Imię", text: $form.name)
                    .textContentType(.givenName)
                LabeledContent("Wiek") {
                    TextField("–", text: $form.age)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Wzrost") {
                    HStack(spacing: 4) {
                        TextField("–", text: $form.height)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(verbatim: "cm").foregroundStyle(.secondary)
                    }
                }
                Picker("Płeć", selection: $form.sex) {
                    ForEach(["", "male", "female"], id: \.self) { Text(Labels.sex($0)).tag($0) }
                }
                if form != original {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Text("Zapisz profil").bold()
                            Spacer()
                            if saving { ProgressView() }
                        }
                    }
                    .disabled(saving)
                }
                if let error { ErrorText(message: error) }
            } header: {
                Text("Profil")
            }
        }
    }

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "pl"
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func load() async {
        do {
            let settings = try await APIClient.shared.settings(person: appState.activePersonId)
            form = settings
            state = .loaded(settings)
        } catch {
            guard !Task.isCancelled else { return }
            if state.value == nil { state = .failed(error.localizedDescription) } else { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        let age = form.age.trimmingCharacters(in: .whitespaces)
        let height = form.height.trimmingCharacters(in: .whitespaces)
        if (!age.isEmpty && Int(age) == nil) || (!height.isEmpty && Int(height) == nil) {
            error = String(localized: "Wiek i wzrost muszą być liczbami.")
            return
        }
        saving = true
        error = nil
        defer { saving = false }
        var body = form
        body.name = form.name.trimmingCharacters(in: .whitespaces)
        body.age = age
        body.height = height
        do {
            try await APIClient.shared.saveSettings(body, person: appState.activePersonId)
            form = body
            state = .loaded(body)
            saved += 1
            try? await appState.loadPeople()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
