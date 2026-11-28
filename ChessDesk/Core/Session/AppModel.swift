import Foundation
import Observation

/// Which backend the app talks to. Release builds always use the server in
/// Info.plist (`CDAPIBaseURL`, chessdesk.app). Debug builds can also use the
/// bundled sample data or a dev server forwarded to localhost.
nonisolated enum Backend: Hashable, Sendable {
    case sampleData
    case server(URL)

    static let localDevelopment = Backend.server(URL(string: "http://localhost:3000").unsafelyUnwrapped)

    static var production: Backend {
        let configured = Bundle.main.object(forInfoDictionaryKey: "CDAPIBaseURL") as? String
        let url = configured.flatMap(URL.init(string:)) ?? URL(string: "https://chessdesk.app").unsafelyUnwrapped
        return .server(url)
    }

    var api: any ChessDeskAPI {
        switch self {
        case .sampleData:
            #if DEBUG
                FixtureAPI(player: FixturePlayer.atLaunch)
            #else
                FixtureAPI()
            #endif
        case let .server(url): LiveAPI(baseURL: url)
        }
    }

    var label: String {
        switch self {
        case .sampleData: "Sample data"
        case let .server(url): url.host() ?? url.absoluteString
        }
    }

    var tokenAccount: String {
        switch self {
        case .sampleData: "sample"
        case let .server(url): url.absoluteString
        }
    }

    #if DEBUG
        private static let defaultsKey = "cd.debug.backend"

        /// Debug default is the sample data: the app API is merged on the
        /// site but not released yet, so production answers 404 for now.
        static var debugDefault: Backend {
            if let argument = UserDefaults.standard.string(forKey: "CDBackend") {
                return parse(argument)
            }
            return parse(UserDefaults.standard.string(forKey: defaultsKey) ?? "sample")
        }

        static func parse(_ text: String) -> Backend {
            switch text {
            case "sample": .sampleData
            case "local": .localDevelopment
            case "production": .production
            default: URL(string: text).map(Backend.server) ?? .sampleData
            }
        }

        func rememberAsDebugChoice() {
            let text = switch self {
            case .sampleData: "sample"
            case let .server(url): self == .localDevelopment ? "local" : self == .production ? "production" : url.absoluteString
            }
            UserDefaults.standard.set(text, forKey: Self.defaultsKey)
        }
    #endif

    static var initial: Backend {
        #if DEBUG
            debugDefault
        #else
            production
        #endif
    }
}

/// The app's shared state: who is signed in, what they may use, and the
/// client to the backend. Views read it from the environment.
@Observable
final class AppModel {
    enum Account: Equatable {
        case guest
        case signedIn(Me)
    }

    private(set) var backend: Backend
    private(set) var api: any ChessDeskAPI
    private(set) var account: Account = .guest
    private(set) var guestProgress: GuestProgress
    /// Stockfish on the device, for the trainers. Nil in previews and tests.
    var judge: (any MoveJudging)?
    /// Bumped whenever the account changes, so screens reload their data.
    private(set) var accountRevision = 0

    private var tokens: any TokenStoring
    private let guestStore: GuestProgressStore
    private let makeTokenStore: @Sendable (Backend) -> any TokenStoring

    init(
        backend: Backend = .initial,
        api: (any ChessDeskAPI)? = nil,
        guestStore: GuestProgressStore = .standard,
        makeTokenStore: @escaping @Sendable (Backend) -> any TokenStoring = {
            KeychainTokenStore(account: $0.tokenAccount)
        }
    ) {
        self.backend = backend
        self.api = api ?? backend.api
        self.guestStore = guestStore
        self.makeTokenStore = makeTokenStore
        tokens = makeTokenStore(backend)
        guestProgress = guestStore.load()
    }

    var token: String? { tokens.read() }

    var me: Me? {
        if case let .signedIn(me) = account { return me }
        return nil
    }

    var isSignedIn: Bool { me != nil }
    var hasPremium: Bool { me?.access.premium ?? false }

    // MARK: Session

    /// Called at launch: a stored token is checked against the server. A
    /// token the server no longer accepts is dropped; being offline keeps it.
    func restoreSession() async {
        #if DEBUG
            if FixturePlayer.atLaunch != nil, backend == .sampleData, token == nil { tokens.write(FixturePlayer.token) }
        #endif
        guard let token else { return }
        do {
            setAccount(.signedIn(try await api.me(token: token)))
            await refreshTokenIfOld(token)
        } catch let error as APIError where error.isUnauthorized {
            tokens.write(nil)
            setAccount(.guest)
        } catch {
            // Offline or a server fault: stay as we are and try at next launch.
        }
    }

    func signIn(email: String, password: String) async throws {
        try await open(api.login(email: email, password: password), withApple: false)
    }

    /// Creates a player account and signs in. What the guest learned on this
    /// device moves to the new account.
    func signUp(firstName: String, lastName: String, email: String, password: String) async throws {
        let session = try await api.signup(firstName: firstName, lastName: lastName, email: email, password: password)
        try await open(session, withApple: false)
    }

    /// Signs in, or creates the account, with what the Apple sheet returned.
    func signIn(with apple: AppleCredential) async throws {
        let session = try await api.signInWithApple(
            identityToken: apple.identityToken, firstName: apple.firstName, lastName: apple.lastName
        )
        try await open(session, withApple: true)
    }

    private func open(_ session: AuthSession, withApple: Bool) async throws {
        tokens.write(session.token)
        do {
            let me = try await api.me(token: session.token)
            usedAppleSignIn = withApple
            setAccount(.signedIn(me))
        } catch {
            tokens.write(nil)
            throw error
        }
        await uploadGuestProgress(token: session.token)
    }

    func signOut() {
        tokens.write(nil)
        usedAppleSignIn = false
        setAccount(.guest)
    }

    /// Whether this device signed in with Apple: deleting the account then
    /// asks Apple once more, so the authorisation can be revoked.
    private(set) var usedAppleSignIn: Bool {
        get { UserDefaults.standard.bool(forKey: appleKey) }
        set { UserDefaults.standard.set(newValue, forKey: appleKey) }
    }

    private var appleKey: String { "cd.session.apple.\(backend.tokenAccount)" }

    /// Asks for the verification email again and re-reads the account, in
    /// case the link was opened in the meantime.
    func resendVerification() async throws {
        guard let token else { return }
        try await api.resendVerification(token: token)
        await reloadAccount()
    }

    func reloadAccount() async {
        guard let token, isSignedIn, let me = try? await api.me(token: token) else { return }
        setAccount(.signedIn(me))
    }

    /// Sends a StoreKit transaction to the server, which verifies it with
    /// Apple and answers with what the account may now use.
    func recordApplePurchase(_ signedTransaction: String) async throws {
        guard let token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
        let me = try await api.recordApplePurchase(signedTransaction: signedTransaction, token: token)
        setAccount(.signedIn(me))
    }

    /// Deletes the account on the server, then forgets the session here.
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?) async throws {
        guard let token else { return }
        try await api.deleteAccount(
            currentPassword: currentPassword, appleAuthorizationCode: appleAuthorizationCode, token: token
        )
        signOut()
    }

    /// A call answered `unauthorized`: the token was revoked or expired.
    func sessionExpired() {
        guard isSignedIn else { return }
        signOut()
    }

    private func refreshTokenIfOld(_ token: String) async {
        // Tokens last 60 days; renewing at every launch keeps an active
        // player signed in for good, and costs one small request.
        if let session = try? await api.refresh(token: token) {
            tokens.write(session.token)
        }
    }

    private func setAccount(_ new: Account) {
        guard new != account else { return }
        account = new
        accountRevision += 1
    }

    // MARK: Guest progress

    func recordGuestGrades(_ grades: [MoveGrade], course: String) {
        guestProgress.record(grades, course: course)
        guestStore.save(guestProgress)
    }

    func recordGuestStage(_ stage: String, path: String) {
        guestProgress.complete(stage: stage, path: path)
        guestStore.save(guestProgress)
    }

    func noteCourseOpened(_ slug: String) {
        guard guestProgress.lastCourse != slug else { return }
        guestProgress.lastCourse = slug
        guestStore.save(guestProgress)
    }

    /// Sends what the guest learned on this device to their account, course
    /// by course; a course that fails stays on the device for the next try.
    private func uploadGuestProgress(token: String) async {
        let pathPrefix = GuestProgress.pathKey("")
        for (key, grades) in guestProgress.grades where !grades.isEmpty {
            let sent: Int?
            if key.hasPrefix(pathPrefix) {
                let slug = String(key.dropFirst(pathPrefix.count))
                sent = try? await api.importLocalPathProgress(slug: slug, grades: grades, token: token)
                if sent != nil { guestProgress.completedStages[slug] = nil }
            } else {
                sent = try? await api.importLocalProgress(slug: key, grades: grades, token: token)
            }
            if sent != nil { guestProgress.grades[key] = nil }
        }
        guestStore.save(guestProgress)
    }

    // MARK: Developer

    #if DEBUG
        func use(_ backend: Backend) {
            guard backend != self.backend else { return }
            backend.rememberAsDebugChoice()
            self.backend = backend
            api = backend.api
            tokens = makeTokenStore(backend)
            account = .guest
            accountRevision += 1
            Task { await restoreSession() }
        }
    #endif
}
