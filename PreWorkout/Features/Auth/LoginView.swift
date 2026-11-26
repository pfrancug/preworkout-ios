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
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                brand
                features
                    .padding(.top, 36)
                Spacer(minLength: 24)
                if ServerConfig.bundledURL == nil {
                    serverField
                        .padding(.bottom, 16)
                }
                appleButton
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
                Text("Logowanie tylko przez Apple. Twoje treningi zostają na Twoim koncie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .overlay {
            if busy { ProgressView().controlSize(.large) }
        }
        .disabled(busy)
        .onAppear {
            Analytics.send("Onboarding.stepViewed", ["step": "signIn"])
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.10),
                Color(red: 0.10, green: 0.12, blue: 0.09),
                Color(red: 0.06, green: 0.07, blue: 0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var brand: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.93, blue: 0.22).opacity(0.16))
                    .frame(width: 96, height: 96)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color(red: 0.72, green: 0.93, blue: 0.22))
            }
            Text("PreWorkout")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Trening na żywo. Postępy w jednym miejscu.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            feature("timer", String(localized: "Trening na żywo"), String(localized: "Timer, przerwa i zapis serii bez odrywania się od ćwiczenia"))
            feature("square.stack.3d.up", String(localized: "Ćwiczenia i sesje"), String(localized: "Biblioteka, superserie, combo i bloki na czas"))
            feature("chart.line.uptrend.xyaxis", String(localized: "Kalorie i waga"), String(localized: "Kalkulator, cel dzienny i historia, która idzie za Tobą"))
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.72, green: 0.93, blue: 0.22))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var serverField: some View {
        TextField("https://…", text: $server)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            configureAppleRequest(request)
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
