import SwiftUI
import UIKit

/// App settings: account (Apple link, sign-out, account deletion), language, server, version.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var linkedFeedback = false
    @State private var error: String?
    @State private var appleRunner = AppleSignInRunner()

    var body: some View {
        Form {
            if let account = appState.account {
                Section {
                    if let email = account.email, !email.isEmpty {
                        LabeledContent("E-mail", value: email)
                    } else if !account.name.isEmpty {
                        LabeledContent("Nazwa", value: account.name)
                    }

                    if account.appleLinked {
                        Label("Połączono z Apple ID", systemImage: "checkmark.circle.fill")
                    } else {
                        Button {
                            Task { await linkWithApple() }
                        } label: {
                            HStack {
                                Text("Powiąż z Apple")
                                if busy {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text("Konto")
                } footer: {
                    if linkedFeedback {
                        Text("Powiązano konto z Apple ID.")
                    } else if !account.appleLinked {
                        Text("Powiąż konto z Apple ID, aby logować się przez Apple.")
                    }
                }
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    LabeledContent("Język") {
                        HStack(spacing: 4) {
                            Text(currentLanguage)
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Język zmienisz w Ustawieniach iOS › PreWorkout › Język.")
            }

            Section("Aplikacja") {
                LabeledContent("Serwer", value: ServerConfig.baseURL?.host() ?? "–")
                LabeledContent("Wersja", value: version)
            }

            Section {
                Button("Wyloguj", role: .destructive) { confirmLogout = true }
                    .disabled(busy)
            }

            if let account = appState.account {
                Section {
                    Button("Usuń konto", role: .destructive) { confirmDelete = true }
                        .disabled(busy || account.isAdmin)
                } footer: {
                    if account.isAdmin {
                        Text("Konto właściciela zawiera pierwotne dane i nie można go usunąć.")
                    } else {
                        Text("Trwale usuwa konto razem ze wszystkimi profilami, wpisami i własnymi ćwiczeniami.")
                    }
                }
            }
        }
        .navigationTitle("Ustawienia")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Wylogować się?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Wyloguj", role: .destructive) { Task { await appState.logout() } }
        }
        .confirmationDialog("Usunąć konto?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń trwale", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Wszystkie Twoje dane zostaną trwale usunięte. Tej operacji nie można cofnąć.")
        }
        .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            if let error { Text(error) }
        }
    }

    private func linkWithApple() async {
        busy = true
        defer { busy = false }
        do {
            guard let payload = try await appleRunner.authorize() else { return }
            try await appState.linkApple(payload)
            linkedFeedback = true
        } catch let apiError as APIError {
            if case .http(let status, let message) = apiError {
                if status == 409 || message == "apple_in_use" {
                    error = String(localized: "To Apple ID jest już używane przez inne konto.")
                } else {
                    error = message
                }
            } else {
                error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        busy = true
        defer { busy = false }
        do {
            try await appState.deleteAccount()
        } catch {
            self.error = error.localizedDescription
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
}
