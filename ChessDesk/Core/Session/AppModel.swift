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
        case .sampleData: FixtureAPI()
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
    /// Bumped whenever the account changes, so screens reload their data.
    private(set) var accountRevision = 0

    private var tokens: any TokenStoring
    private let guestStore: GuestProgressStore
    private let makeTokenStore: @Sendable (Backend) -> any TokenStoring

    init(
        backend: Backend = .initial,
        guestStore: GuestProgressStore = .standard,
        makeTokenStore: @escaping @Sendable (Backend) -> any TokenStoring = {
            KeychainTokenStore(account: $0.tokenAccount)
        }
    ) {
        self.backend = backend
        api = backend.api
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
        let session = try await api.login(email: email, password: password)
        tokens.write(session.token)
        let me = try await api.me(token: session.token)
        setAccount(.signedIn(me))
        await uploadGuestProgress(token: session.token)
    }

    func signOut() {
        tokens.write(nil)
        setAccount(.guest)
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

    func noteCourseOpened(_ slug: String) {
        guard guestProgress.lastCourse != slug else { return }
        guestProgress.lastCourse = slug
        guestStore.save(guestProgress)
    }

    /// Sends what the guest learned on this device to their account, course
    /// by course; a course that fails stays on the device for the next try.
    private func uploadGuestProgress(token: String) async {
        for (slug, grades) in guestProgress.grades where !grades.isEmpty {
            if (try? await api.importLocalProgress(slug: slug, grades: grades, token: token)) != nil {
                guestProgress.grades[slug] = nil
            }
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
