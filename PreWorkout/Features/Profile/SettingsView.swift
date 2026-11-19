import SwiftUI
import UIKit

/// App settings: language (iOS per-app setting), server, version, sign-out.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var confirmLogout = false

    var body: some View {
        Form {
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
            }
        }
        .navigationTitle("Ustawienia")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Wylogować się?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Wyloguj", role: .destructive) { Task { await appState.logout() } }
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
