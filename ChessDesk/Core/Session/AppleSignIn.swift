import AuthenticationServices
import UIKit

/// What the Sign in with Apple sheet hands back, reduced to what the server
/// needs. The identity token is checked by the server against Apple's keys;
/// the app never reads it.
nonisolated struct AppleCredential: Equatable, Sendable {
    let identityToken: String
    /// Single use, five minutes: lets the server tell Apple an account is gone.
    let authorizationCode: String?
    /// Apple gives the name once, the first time the person authorises the app.
    let firstName: String?
    let lastName: String?

    init(identityToken: String, authorizationCode: String? = nil, firstName: String? = nil, lastName: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.firstName = firstName
        self.lastName = lastName
    }

    init?(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        self.init(
            identityToken: token,
            authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName
        )
    }
}

nonisolated enum AppleSignInError: Error {
    /// The person closed the sheet: nothing to report.
    case cancelled
    case failed

    init(_ error: any Error) {
        self = (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .failed
    }

    static let message = "Sign in with Apple did not complete. Try again."
}

/// Runs the Apple sheet outside a `SignInWithAppleButton`: deleting an
/// account asks Apple once more, to get a fresh authorisation code.
final class AppleAuthorizer: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, any Error>?

    func authorize() async throws -> AppleCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let credential = AppleCredential(authorization) {
            finish(.success(credential))
        } else {
            finish(.failure(AppleSignInError.failed))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(AppleSignInError(error)))
    }

    private func finish(_ result: Result<AppleCredential, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
