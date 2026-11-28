import Foundation

/// Answers from the captured files in `Fixtures/api-v1` (real answers of the
/// site's dev server, guest viewer). It is what Debug builds start on, and
/// what previews and tests always use.
///
/// It plays a guest, everywhere: routes that need an account answer
/// `unauthorized`, and a Premium line answers `premium_required`, as the
/// server does. With a `player`, it plays that signed-in player instead: the
/// sample player (`FixturePlayer`, synthetic data), whose home, games,
/// repertoire and explorer speak of the same games.
nonisolated struct FixtureAPI: ChessDeskAPI {
    /// Simulated latency, so loading states are visible while developing.
    var delay: Duration = .milliseconds(250)
    /// The signed-in player it plays, or nil for a guest.
    var player: FixturePlayer?

    private static let detailedSlugs = ["practical-caro-kann", "aggressive-1e4", "practical-london-system"]

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/api-v1")
        else { throw APIError.unreadable }
        return try Data(contentsOf: url)
    }

    private func load<Response: Decodable>(_ name: String) async throws -> Response {
        try await Task.sleep(for: delay)
        return try LiveAPI.decode(status: 200, data: Self.data(name))
    }

    private var signInNeeded: APIError {
        .server(status: 401, code: "unauthorized", message: "Sign in to continue.")
    }

    func login(email: String, password: String) async throws -> AuthSession {
        try await Task.sleep(for: delay)
        throw APIError.server(
            status: 401,
            code: "invalid_credentials",
            message: "Sample data has no accounts. Switch to a server in Developer settings to sign in."
        )
    }

    private var noAccounts: APIError {
        .server(
            status: 422,
            code: "request_failed",
            message: "Sample data has no accounts. Switch to a server in Developer settings to create one."
        )
    }

    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession {
        try await Task.sleep(for: delay)
        throw noAccounts
    }

    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession {
        try await Task.sleep(for: delay)
        throw noAccounts
    }

    func resendVerification(token: String) async throws { throw signInNeeded }
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {
        throw signInNeeded
    }

    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me { throw signInNeeded }
    func refresh(token: String) async throws -> AuthSession { throw signInNeeded }
    func me(token: String) async throws -> Me { try signedInPlayer().me() }

    func courses(token: String?) async throws -> [CourseCard] {
        let response: CoursesResponse = try await load("courses")
        return player?.courses(response.courses) ?? response.courses
    }

    func course(slug: String, token: String?) async throws -> CourseDetail {
        guard Self.detailedSlugs.contains(slug) else {
            try await Task.sleep(for: delay)
            throw APIError.server(
                status: 404,
                code: "not_found",
                message: "Sample data holds three courses: the Caro-Kann Bunker, the Buccaneer 1.e4 and the Big Ben London."
            )
        }
        let course: CourseDetail = try await load("course-\(slug)")
        return player?.course(course) ?? course
    }

    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        guard mode == .learn else {
            // A review belongs to an account: the sample player has one course to review.
            guard let player, slug == FixturePlayer.courseSlug else {
                try await Task.sleep(for: delay)
                throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to review your lines.")
            }
            return player.courseReview(from: try await load("session-learn-\(slug)"))
        }
        let session: CourseSession = try await load("session-learn-\(slug)")
        if let line, !session.lines.contains(where: { $0.id == line }) {
            throw APIError.server(status: 403, code: "premium_required", message: "This line is part of Premium.")
        }
        return session
    }

    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws { throw signInNeeded }
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { throw signInNeeded }
    /// The sample player keeps the grades of their repertoires and of their course.
    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {
        let player = try signedInPlayer()
        if deck == FixturePlayer.courseDeck {
            player.recordCourseGrades()
        } else {
            await player.openings.record(deck: deck, grades: grades)
        }
    }

    func due(token: String) async throws -> DueSummary {
        let player = try signedInPlayer()
        let courses: CoursesResponse = try LiveAPI.decode(status: 200, data: Self.data("courses"))
        let title = courses.courses.first { $0.slug == FixturePlayer.courseSlug }?.title ?? ""
        return await player.due(courseTitle: title)
    }

    // MARK: The player's own games (an account is needed)

    func accounts(token: String) async throws -> [LinkedAccount] { try signedInPlayer().accounts() }
    func linkAccount(_ provider: GameProvider, username: String, token: String) async throws -> LinkedAccount {
        try await Task.sleep(for: delay)
        return try signedInPlayer().link(provider, username: username)
    }
    func unlinkAccount(_ provider: GameProvider, token: String) async throws { try signedInPlayer().unlink(provider) }
    func importGames(_ provider: GameProvider, mode: ImportMode, cursor: String?, token: String) async throws -> ImportChunk {
        _ = try signedInPlayer()
        try await Task.sleep(for: delay)
        return ImportChunk(imported: 0, totalSoFar: 0, nextCursor: nil, done: true)
    }
    func games(cursor: String?, token: String) async throws -> GamesPage { try signedInPlayer().games(cursor: cursor) }
    func game(id: String, token: String) async throws -> GameDetail { try signedInPlayer().game(id: id) }
    func setStar(game: String, starred: Bool, token: String) async throws {
        try signedInPlayer().setStar(game: game, starred: starred)
    }
    func saveReview(game: String, review: GameReview, token: String) async throws {
        try signedInPlayer().noteReviewed(game: game)
    }
    func mistakes(token: String) async throws -> MistakeQueue { try signedInPlayer().mistakes() }
    func recordMistakeAttempt(_ mistake: String, result: MistakeResult, token: String) async throws -> MistakeAttempt {
        _ = try signedInPlayer()
        return MistakeAttempt(intervalDays: result == .solved ? 3 : 1)
    }

    // MARK: Learning paths

    /// The three free stages of Reach 1000 Elo are captured.
    static let capturedStages = ["fight-for-the-centre", "develop-your-pieces", "castle-early"]

    func paths(token: String?) async throws -> [PathCard] {
        let response: PathsResponse = try await load("paths")
        return response.paths
    }

    func path(slug: String, token: String?) async throws -> PathDetail {
        guard slug == "reach-1000-elo" else {
            try await Task.sleep(for: delay)
            throw APIError.server(status: 404, code: "not_found", message: "Sample data holds one path: Reach 1000 Elo.")
        }
        return try await load("path-\(slug)")
    }

    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        let wanted = stage ?? Self.capturedStages[0]
        guard slug == "reach-1000-elo", Self.capturedStages.contains(wanted) else {
            try await Task.sleep(for: delay)
            throw APIError.server(status: 403, code: "premium_required", message: "This stage is part of Premium.")
        }
        return try await load("path-session-\(wanted)")
    }

    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int {
        throw signInNeeded
    }
}

private final class BundleToken {}
