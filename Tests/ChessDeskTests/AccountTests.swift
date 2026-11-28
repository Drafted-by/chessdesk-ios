import Foundation
import Testing
@testable import ChessDesk

/// A server with accounts, in memory: enough to follow a player from the
/// sign-up form to the deletion of the account.
private final class AccountServer: ChessDeskAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private let failMe: Bool
    private let hasPassword: Bool
    private let guest = FixtureAPI(delay: .zero)

    init(failMe: Bool = false, hasPassword: Bool = true) {
        self.failMe = failMe
        self.hasPassword = hasPassword
    }

    var log: [String] { lock.withLock { calls } }
    private func note(_ call: String) { lock.withLock { calls.append(call) } }

    private func session(_ token: String, verified: Bool) -> AuthSession {
        AuthSession(
            token: token,
            expiresAt: Date(timeIntervalSinceNow: 3600),
            user: APIUser(id: "u1", email: "ana@example.com", name: "Ana Silva", role: "STUDENT", emailVerified: verified)
        )
    }

    func login(email: String, password: String) async throws -> AuthSession {
        note("login")
        return session("login-token", verified: true)
    }

    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession {
        note("signup \(firstName) \(lastName) \(email)")
        return session("signup-token", verified: false)
    }

    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession {
        note("apple \(identityToken) \(firstName ?? "-")")
        return session("apple-token", verified: true)
    }

    func resendVerification(token: String) async throws { note("resend \(token)") }

    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {
        note("delete \(currentPassword ?? "-") \(appleAuthorizationCode ?? "-") \(token)")
        if currentPassword == "wrong" {
            throw APIError.server(status: 422, code: "request_failed", message: "Current password is incorrect.")
        }
    }

    func refresh(token: String) async throws -> AuthSession { session(token, verified: true) }

    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me {
        note("purchase \(token)")
        return try await me(token: token)
    }

    func me(token: String) async throws -> Me {
        note("me \(token)")
        if failMe { throw APIError.offline }
        return Me(
            user: session(token, verified: token != "signup-token").user,
            hasPassword: hasPassword,
            access: .init(
                premium: false, paid: false, viaCoachPlan: false, viaAppStore: false,
                trial: .init(status: "available", endsAt: nil, daysLeft: nil)
            ),
            freeLimits: .init(repertoireLines: 20, explorerGames: 100)
        )
    }

    func courses(token: String?) async throws -> [CourseCard] { try await guest.courses(token: token) }
    func course(slug: String, token: String?) async throws -> CourseDetail { try await guest.course(slug: slug, token: token) }
    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        try await guest.courseSession(slug: slug, mode: mode, line: line, token: token)
    }

    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws {}
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int {
        note("import \(slug) \(grades.count)")
        return grades.count
    }

    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {}
    func due(token: String) async throws -> DueSummary { try await guest.due(token: token) }
    func paths(token: String?) async throws -> [PathCard] { try await guest.paths(token: token) }
    func path(slug: String, token: String?) async throws -> PathDetail { try await guest.path(slug: slug, token: token) }
    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        try await guest.pathSession(slug: slug, stage: stage, token: token)
    }

    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { grades.count }
}

@MainActor
@Suite(.serialized) struct AccountTests {
    private func model(_ server: AccountServer) -> (AppModel, MemoryTokenStore) {
        let tokens = MemoryTokenStore()
        let file = FileManager.default.temporaryDirectory.appending(path: "cd-account-\(UUID().uuidString).json")
        let app = AppModel(
            backend: .sampleData,
            api: server,
            guestStore: GuestProgressStore(url: file),
            makeTokenStore: { _ in tokens }
        )
        return (app, tokens)
    }

    @Test func signingUpOpensTheAccountNotYetVerified() async throws {
        let server = AccountServer()
        let (app, tokens) = model(server)
        try await app.signUp(firstName: "Ana", lastName: "Silva", email: "ana@example.com", password: "longenough")
        #expect(tokens.read() == "signup-token")
        #expect(app.me?.user.emailVerified == false)
        #expect(app.usedAppleSignIn == false)
        #expect(server.log.first == "signup Ana Silva ana@example.com")
    }

    @Test func askingForTheLinkAgainRereadsTheAccount() async throws {
        let server = AccountServer()
        let (app, _) = model(server)
        try await app.signUp(firstName: "Ana", lastName: "Silva", email: "ana@example.com", password: "longenough")
        try await app.resendVerification()
        #expect(server.log.suffix(2) == ["resend signup-token", "me signup-token"])
    }

    @Test func aSessionThatCannotBeReadIsNotKept() async {
        let (app, tokens) = model(AccountServer(failMe: true))
        await #expect(throws: APIError.offline) {
            try await app.signUp(firstName: "Ana", lastName: "Silva", email: "ana@example.com", password: "longenough")
        }
        #expect(tokens.read() == nil)
        #expect(!app.isSignedIn)
    }

    @Test func appleSignInForwardsTheNameAndIsRemembered() async throws {
        let server = AccountServer(hasPassword: false)
        let (app, tokens) = model(server)
        try await app.signIn(with: AppleCredential(identityToken: "jwt", firstName: "Ana", lastName: "Silva"))
        #expect(tokens.read() == "apple-token")
        #expect(app.me?.hasPassword == false)
        #expect(app.usedAppleSignIn)
        #expect(server.log.first == "apple jwt Ana")
        app.signOut()
        #expect(!app.usedAppleSignIn)
    }

    @Test func deletingTheAccountEndsTheSessionHere() async throws {
        let server = AccountServer()
        let (app, tokens) = model(server)
        try await app.signIn(email: "ana@example.com", password: "pw")
        try await app.deleteAccount(currentPassword: "hunter22", appleAuthorizationCode: nil)
        #expect(server.log.last == "delete hunter22 - login-token")
        #expect(tokens.read() == nil)
        #expect(!app.isSignedIn)
    }

    @Test func aRefusedDeletionKeepsThePlayerSignedIn() async throws {
        let (app, tokens) = model(AccountServer())
        try await app.signIn(email: "ana@example.com", password: "pw")
        await #expect(throws: APIError.self) {
            try await app.deleteAccount(currentPassword: "wrong", appleAuthorizationCode: nil)
        }
        #expect(tokens.read() == "login-token")
        #expect(app.isSignedIn)
    }

    @Test func meDecodesFromAServerOlderThanAccountCreation() throws {
        let json = #"{"user":{"id":"u1","email":"a@b.co","name":"A","role":"STUDENT","emailVerified":true},"access":{"premium":false,"paid":false,"viaCoachPlan":false,"trial":{"status":"available","endsAt":null,"daysLeft":null}},"freeLimits":{"repertoireLines":20,"explorerGames":100}}"#
        let me = try APICoding.decoder.decode(Me.self, from: Data(json.utf8))
        #expect(me.hasPassword == nil)
    }
}
