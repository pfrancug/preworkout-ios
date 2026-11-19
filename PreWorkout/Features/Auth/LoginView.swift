import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var server = ServerConfig.baseURL?.absoluteString ?? ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Hasło", text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }

                Section("Serwer") {
                    TextField("https://…", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Zaloguj").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || password.isEmpty)
                }
            }
            .navigationTitle("PreWorkout")
            .onAppear { passwordFocused = true }
        }
    }

    private func signIn() {
        guard !password.isEmpty else { return }
        guard let url = ServerConfig.parse(server) else {
            error = String(localized: "Podaj adres serwera (https://…).")
            return
        }
        ServerConfig.setOverride(url == ServerConfig.bundledURL ? nil : url)
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await appState.login(password: password)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
