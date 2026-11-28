import AuthenticationServices
import CryptoKit
import UIKit

// Continue with Google, without a Google SDK. The app opens the site's own
// Google sign-in in the system's sign-in sheet; the site ends it by coming
// back to `chessdesk://auth/google` with a one-time code, which the server
// exchanges for a session only together with a secret this app made up
// before starting (PKCE): a code read by anyone else is of no use.

/// What the sheet hands back: the one-time code and the secret that goes with it.
nonisolated struct GoogleCredential: Equatable, Sendable {
    let code: String
    let codeVerifier: String
}

nonisolated enum GoogleSignInError: Error, Equatable {
    /// The person closed the sheet: nothing to report.
    case cancelled
    /// A coach account: those sign in with email and password.
    case coach
    /// Google sign-in is not offered by this server.
    case unavailable
    case failed

    var message: String {
        switch self {
        case .cancelled: ""
        case .coach: "Coach accounts sign in with their email and password."
        case .unavailable: "Google sign-in is not available right now. Use your email instead."
        case .failed: "Google sign-in did not complete. Try again."
        }
    }
}

/// The two ends of the exchange, as values: the secret and its challenge on
/// the way out, the reading of the address the sheet comes back to.
nonisolated enum GoogleHandoff {
    static let scheme = "chessdesk"

    /// 32 random bytes, base64url: 43 characters of the PKCE alphabet.
    static func makeVerifier() -> String {
        // `UInt8.random` draws from the system's cryptographic generator.
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    /// base64url(SHA-256(verifier)), as RFC 7636 writes it.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func startURL(server: URL, challenge: String) -> URL {
        server.appending(path: "api/v1/auth/google/start")
            .appending(queryItems: [URLQueryItem(name: "code_challenge", value: challenge)])
    }

    /// `chessdesk://auth/google?code=…` or `?error=coach|unavailable|failed`.
    static func read(_ callback: URL, verifier: String) -> Result<GoogleCredential, GoogleSignInError> {
        guard callback.scheme == scheme, callback.host() == "auth", callback.path() == "/google",
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        else { return .failure(.failed) }
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(GoogleCredential(code: code, codeVerifier: verifier))
        }
        switch items.first(where: { $0.name == "error" })?.value {
        case "coach": return .failure(.coach)
        case "unavailable": return .failure(.unavailable)
        default: return .failure(.failed)
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Runs the system's sign-in sheet on the site's Google sign-in.
final class GoogleAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(server: URL) async throws -> GoogleCredential {
        let verifier = GoogleHandoff.makeVerifier()
        let start = GoogleHandoff.startURL(server: server, challenge: GoogleHandoff.challenge(for: verifier))
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: start, callbackURLScheme: GoogleHandoff.scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? GoogleSignInError.cancelled : GoogleSignInError.failed)
                }
            }
            session.presentationContextProvider = self
            // The person's own browser session: already signed in to Google there, one tap.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { continuation.resume(throwing: GoogleSignInError.failed) }
        }
        session = nil
        return try GoogleHandoff.read(callback, verifier: verifier).get()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
