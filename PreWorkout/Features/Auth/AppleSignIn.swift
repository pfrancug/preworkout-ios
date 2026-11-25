import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum AppleAuthError: LocalizedError {
    case missingToken
    case randomFailed

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return String(localized: "Apple nie zwrócił tokenu logowania.")
        case .randomFailed:
            return String(localized: "Nie udało się rozpocząć logowania przez Apple.")
        }
    }
}

struct AppleCredentialPayload {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String
    let fullName: String?

    init(credential: ASAuthorizationAppleIDCredential, nonce: String) throws {
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            throw AppleAuthError.missingToken
        }
        identityToken = token
        authorizationCode = credential.authorizationCode.flatMap {
            let code = String(data: $0, encoding: .utf8)
            return code?.isEmpty == false ? code : nil
        }
        self.nonce = nonce
        if let name = credential.fullName {
            let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            fullName = formatted.isEmpty ? nil : formatted
        } else {
            fullName = nil
        }
    }
}

enum AppleNonce {
    static func random(length: Int = 32) throws -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw AppleAuthError.randomFailed }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Triggers native Sign in with Apple from a regular SwiftUI button (e.g. account linking in Settings).
@MainActor
final class AppleSignInRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredentialPayload?, Error>?
    private var currentNonce: String?
    private var activeController: ASAuthorizationController?

    func authorize() async throws -> AppleCredentialPayload? {
        let nonce = try AppleNonce.random()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            defer { cleanup() }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce else {
                continuation?.resume(throwing: AppleAuthError.missingToken)
                return
            }
            do {
                continuation?.resume(returning: try AppleCredentialPayload(credential: credential, nonce: nonce))
            } catch {
                continuation?.resume(throwing: error)
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            defer { cleanup() }
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                continuation?.resume(returning: nil)
            } else {
                continuation?.resume(throwing: error)
            }
        }
    }

    private func cleanup() {
        continuation = nil
        currentNonce = nil
        activeController = nil
    }
}
