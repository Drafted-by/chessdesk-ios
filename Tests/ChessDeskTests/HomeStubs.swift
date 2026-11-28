import Foundation
@testable import ChessDesk

/// Test stubs implement what they exercise; the home, Daily 5 and settings
/// calls default to "not signed in". Kept in their own file (as the play
/// stubs are) so the branches adding features do not edit the same lines.
nonisolated extension ChessDeskAPI {
    private var homeNotStubbed: APIError { .server(status: 401, code: "unauthorized", message: "Not stubbed.") }
    func home(token: String) async throws -> PlayerHome { throw homeNotStubbed }
    func progress(token: String) async throws -> ProgressPage { throw homeNotStubbed }
    func patternDrill(key: String, token: String) async throws -> PatternDrill { throw homeNotStubbed }
    func daily(again: Bool, token: String) async throws -> DailyPlan { throw homeNotStubbed }
    func startDaily(_ request: DailySessionRequest, token: String) async throws -> DailySessionStart { throw homeNotStubbed }
    func completeDaily(_ request: DailyCompletionRequest, token: String) async throws -> DailyCompletion { throw homeNotStubbed }
    func setReminder(_ request: ReminderRequest, token: String) async throws -> DailyReminder { throw homeNotStubbed }
    func dismissReminderOffer(token: String) async throws { throw homeNotStubbed }
    func setRatingGoal(_ request: RatingGoalRequest, token: String) async throws -> RatingGoal { throw homeNotStubbed }
    func completeOnboarding(token: String) async throws { throw homeNotStubbed }
    func dismissFirstReport(token: String) async throws { throw homeNotStubbed }
    func settings(token: String) async throws -> AccountSettings { throw homeNotStubbed }
    func updateSettings(_ request: UpdateSettingsRequest, token: String) async throws -> AccountSettings { throw homeNotStubbed }
    func setPrimaryRating(source: String, format: String, token: String) async throws -> AccountRatings { throw homeNotStubbed }
}
