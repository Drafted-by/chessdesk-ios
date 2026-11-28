import Foundation

/// The signed-in player's home, progress and Daily 5. Every operation needs
/// an account: a guest never calls them.
nonisolated protocol HomeAPI {
    func home(token: String) async throws -> PlayerHome
    func progress(token: String) async throws -> ProgressPage
    func patternDrill(key: String, token: String) async throws -> PatternDrill
    /// Today's positions; `again` asks for five more once the day's session is done.
    func daily(again: Bool, token: String) async throws -> DailyPlan
    /// Opens today's session (idempotent per local day) and records the time zone.
    func startDaily(_ request: DailySessionRequest, token: String) async throws -> DailySessionStart
    /// Closes today's session and moves the streak; a second call the same day does not count.
    func completeDaily(_ request: DailyCompletionRequest, token: String) async throws -> DailyCompletion
    func setReminder(_ request: ReminderRequest, token: String) async throws -> DailyReminder
    /// "Not now" on the reminder offered after a session: it is not offered again.
    func dismissReminderOffer(token: String) async throws
    func setRatingGoal(_ request: RatingGoalRequest, token: String) async throws -> RatingGoal
    /// "Where do you play?" is answered or skipped.
    func completeOnboarding(token: String) async throws
    func dismissFirstReport(token: String) async throws
}

extension LiveAPI: HomeAPI {
    func home(token: String) async throws -> PlayerHome {
        try await homeExchange("GET", "home", token: token)
    }

    func progress(token: String) async throws -> ProgressPage {
        try await homeExchange("GET", "progress", token: token)
    }

    func patternDrill(key: String, token: String) async throws -> PatternDrill {
        try await homeExchange("GET", "progress/patterns/\(key)", token: token)
    }

    func daily(again: Bool, token: String) async throws -> DailyPlan {
        let query = again ? [URLQueryItem(name: "again", value: "1")] : []
        return try await homeExchange("GET", "daily", query: query, token: token)
    }

    func startDaily(_ request: DailySessionRequest, token: String) async throws -> DailySessionStart {
        try await homeExchange("POST", "daily/session", token: token, body: request)
    }

    func completeDaily(_ request: DailyCompletionRequest, token: String) async throws -> DailyCompletion {
        try await homeExchange("POST", "daily/completion", token: token, body: request)
    }

    func setReminder(_ request: ReminderRequest, token: String) async throws -> DailyReminder {
        try await homeExchange("PUT", "habit/reminder", token: token, body: request)
    }

    func dismissReminderOffer(token: String) async throws {
        let _: OkResponse = try await homeExchange("POST", "habit/reminder/dismiss", token: token)
    }

    func setRatingGoal(_ request: RatingGoalRequest, token: String) async throws -> RatingGoal {
        try await homeExchange("PUT", "habit/goal", token: token, body: request)
    }

    func completeOnboarding(token: String) async throws {
        let _: OkResponse = try await homeExchange("POST", "onboarding/complete", token: token)
    }

    func dismissFirstReport(token: String) async throws {
        let _: OkResponse = try await homeExchange("POST", "onboarding/first-report/dismiss", token: token)
    }
}

extension LiveAPI {
    /// The transport of `LiveAPI` is private to its file; this is the same
    /// exchange, for the routes of the home and the settings.
    func homeExchange<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        token: String?,
        body: (any Encodable)? = nil
    ) async throws -> Response {
        var request = request(method, path, query: query, token: token)
        if let body {
            request.httpBody = try APICoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreadable }
        return try Self.decode(status: http.statusCode, data: data)
    }
}

extension FixtureAPI: HomeAPI {
    func home(token: String) async throws -> PlayerHome {
        try await Task.sleep(for: delay)
        return try signedInPlayer().home()
    }

    func progress(token: String) async throws -> ProgressPage {
        try await Task.sleep(for: delay)
        return try signedInPlayer().progress()
    }

    func patternDrill(key: String, token: String) async throws -> PatternDrill {
        try await Task.sleep(for: delay)
        return try signedInPlayer().patternDrill(key: key)
    }

    func daily(again: Bool, token: String) async throws -> DailyPlan {
        try await Task.sleep(for: delay)
        return try signedInPlayer().daily(again: again)
    }

    func startDaily(_ request: DailySessionRequest, token: String) async throws -> DailySessionStart {
        try await Task.sleep(for: delay)
        return try signedInPlayer().startDaily()
    }

    func completeDaily(_ request: DailyCompletionRequest, token: String) async throws -> DailyCompletion {
        try await Task.sleep(for: delay)
        return try signedInPlayer().completeDaily()
    }

    func setReminder(_ request: ReminderRequest, token: String) async throws -> DailyReminder {
        try await Task.sleep(for: delay)
        return try signedInPlayer().setReminder(request)
    }

    func dismissReminderOffer(token: String) async throws {
        try await Task.sleep(for: delay)
        try signedInPlayer().dismissReminderOffer()
    }

    func setRatingGoal(_ request: RatingGoalRequest, token: String) async throws -> RatingGoal {
        try await Task.sleep(for: delay)
        return try signedInPlayer().setRatingGoal(request)
    }

    func completeOnboarding(token: String) async throws {
        try await Task.sleep(for: delay)
        try signedInPlayer().completeOnboarding()
    }

    func dismissFirstReport(token: String) async throws {
        try await Task.sleep(for: delay)
        try signedInPlayer().dismissFirstReport()
    }

    /// The fixture player, or the server's answer to a guest.
    func signedInPlayer() throws -> FixturePlayer {
        guard let player else {
            throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.")
        }
        return player
    }
}
