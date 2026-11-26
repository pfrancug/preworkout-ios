import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var server = ServerConfig.baseURL?.absoluteString ?? ""
    @State private var pendingNonce: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if ServerConfig.bundledURL == nil {
                    Section("Serwer") {
                        TextField("https://…", text: $server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    SignInWithAppleButton(.signIn) { request in
                        configureAppleRequest(request)
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .disabled(busy)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("PreWorkout")
        }
    }

    private func applyServerURL() -> Bool {
        guard let url = ServerConfig.parse(server) else {
            error = String(localized: "Podaj adres serwera (https://…).")
            return false
        }
        ServerConfig.setOverride(url == ServerConfig.bundledURL ? nil : url)
        return true
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        error = nil
        do {
            let nonce = try AppleNonce.random()
            pendingNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(nonce)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        let nonce = pendingNonce
        pendingNonce = nil

        switch result {
        case .failure(let err):
            if let authError = err as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            error = err.localizedDescription
        case .success(let authorization):
            guard applyServerURL() else { return }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce else {
                error = AppleAuthError.missingToken.localizedDescription
                return
            }
            let payload: AppleCredentialPayload
            do {
                payload = try AppleCredentialPayload(credential: credential, nonce: nonce)
            } catch {
                self.error = error.localizedDescription
                return
            }
            busy = true
            error = nil
            Task {
                defer { busy = false }
                do {
                    try await appState.signInWithApple(payload)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
