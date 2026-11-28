import Foundation

/// A signed-in player for the fixture client, so the home, progress, Daily 5
/// and settings run offline in previews, tests and screenshots.
///
/// SYNTHETIC DATA. The `player-*.json` files in `Fixtures/api-v1` were written
/// by hand from the contract's schemas, not captured from a server: there is
/// no production test account. Names, games, ratings and positions are
/// invented; the positions are checked legal by `HomeFixtureTests`.
///
/// It keeps what the player changes (the Daily 5 done, settings, the goal,
/// the onboarding answered) for the life of the client, like a server would.
nonisolated final class FixturePlayer: @unchecked Sendable {
    /// The token the debug launch option stores; any token works with the fixture client.
    static let token = "fixture-player"

    private struct State {
        var dailyDone = false
        var welcomeAnswered: Bool
        var firstReportDismissed = false
        var reminderOffered = false
        var goal: RatingGoal?
        var goalCleared = false
        var settings: AccountSettings?
        var accounts: [LinkedAccount]
    }

    private let lock = NSLock()
    private var state: State

    /// `welcome`: the player has no linked account yet, and the home asks
    /// "Where do you play?" until it is answered or skipped.
    init(welcome: Bool = false) {
        let lichess = LinkedAccount(
            provider: .lichess, username: "quietrook", lastSyncedAt: .now.addingTimeInterval(-3600),
            historyComplete: true, ratings: ["blitz": 1342, "rapid": 1415]
        )
        state = State(welcomeAnswered: !welcome, accounts: welcome ? [] : [lichess])
    }

    private func withState<Value>(_ body: (inout State) throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    private static func load<Value: Decodable>(_ name: String) throws -> Value {
        try LiveAPI.decode(status: 200, data: FixtureAPI.data(name))
    }

    /// The device's local day, YYYY-MM-DD, as the server computes it from the time zone.
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    // MARK: Account

    func me() throws -> Me { try Self.load("player-me") }

    func accounts() -> [LinkedAccount] { withState { $0.accounts } }

    func link(_ provider: GameProvider, username: String) -> LinkedAccount {
        let account = LinkedAccount(
            provider: provider, username: username, lastSyncedAt: .now, historyComplete: false, ratings: [:]
        )
        withState { state in
            state.accounts.removeAll { $0.provider == provider }
            state.accounts.append(account)
        }
        return account
    }

    func unlink(_ provider: GameProvider) {
        withState { $0.accounts.removeAll { $0.provider == provider } }
    }

    func games() throws -> GamesPage { try Self.load("player-games") }
    func game(id: String) throws -> GameDetail { try Self.load("player-game") }
    func mistakes() throws -> MistakeQueue { try Self.load("player-mistakes") }

    // MARK: Home

    func home() throws -> PlayerHome {
        var home: PlayerHome = try Self.load("player-home")
        let state = withState { $0 }
        if state.dailyDone {
            home.daily.doneToday = true
            home.daily.streak = doneStreak(home.daily.streak)
            home.daily.line = "Day \(home.daily.streak.current), done"
            home.daily.recentDays.append(Self.today)
            home.today.removeAll { $0.target.kind.value == .daily }
            if !home.today.isEmpty { home.today[0].primary = true }
        }
        if !state.welcomeAnswered {
            home.onboarding.needsWelcome = true
            home.onboarding.firstReport = nil
            home.totalGames = 0
        }
        if state.firstReportDismissed { home.onboarding.firstReport = nil }
        home.daily.day = Self.today
        let homeGoal = goal(home.progress?.goal, state: state)
        home.progress?.goal = homeGoal
        return home
    }

    func progress() throws -> ProgressPage {
        var page: ProgressPage = try Self.load("player-progress")
        let state = withState { $0 }
        page.day = Self.today
        if state.dailyDone {
            page.streak = doneStreak(page.streak)
            page.line = "Day \(page.streak.current), done"
            if !page.calendar.isEmpty { page.calendar[page.calendar.count - 1] = 1 }
        }
        let pageGoal = goal(page.progress.goal, state: state)
        page.progress.goal = pageGoal
        return page
    }

    func patternDrill(key: String) throws -> PatternDrill {
        let drill: PatternDrill = try Self.load("player-pattern-drill")
        guard drill.key == key else {
            throw APIError.server(status: 404, code: "not_found", message: "This pattern is no longer in your games.")
        }
        return drill
    }

    // MARK: Daily 5

    func daily(again: Bool) throws -> DailyPlan {
        var plan: DailyPlan = try Self.load("player-daily")
        plan.day = Self.today
        if withState({ $0.dailyDone }) {
            plan.doneToday = true
            plan.streak = doneStreak(plan.streak)
            plan.line = "Day \(plan.streak.current), done"
            if !again {
                plan.items = []
                plan.source = nil
            }
        }
        return plan
    }

    func startDaily() throws -> DailySessionStart {
        DailySessionStart(alreadyDone: withState { $0.dailyDone })
    }

    func completeDaily() throws -> DailyCompletion {
        let plan: DailyPlan = try Self.load("player-daily")
        let (counted, offer) = withState { state -> (Bool, Bool) in
            let counted = !state.dailyDone
            state.dailyDone = true
            let offer = counted && !state.reminderOffered && (state.settings?.reminder.channel.value ?? .off) == .off
            state.reminderOffered = true
            return (counted, offer)
        }
        let after = doneStreak(plan.streak)
        return DailyCompletion(
            counted: counted, streak: after.current, longest: after.longest, freezes: after.freezes,
            extended: counted, freezeUsed: 0, earnedFreeze: false, sessionsDone: 12,
            reminder: .init(channel: .init(.off), hour: nil), offerReminder: offer
        )
    }

    private func doneStreak(_ streak: DailyStreak) -> DailyStreak {
        let current = streak.doneToday ? streak.current : streak.current + 1
        return DailyStreak(
            current: current, longest: max(streak.longest, current), freezes: streak.freezes, doneToday: true,
            coveredByFreeze: streak.coveredByFreeze, nextFreezeIn: streak.nextFreezeIn.map { max(1, $0 - 1) }
        )
    }

    func setReminder(_ request: ReminderRequest) throws -> DailyReminder {
        let reminder = DailyReminder(
            channel: .init(request.channel),
            hour: request.channel == .off ? nil : request.hour,
            timezone: request.tz ?? TimeZone.current.identifier
        )
        try withState { state in
            if state.settings == nil { state.settings = try Self.load("player-settings") }
            state.settings?.reminder = reminder
            state.reminderOffered = true
        }
        return reminder
    }

    func dismissReminderOffer() throws {
        withState { $0.reminderOffered = true }
    }

    // MARK: Goal and onboarding

    func setRatingGoal(_ request: RatingGoalRequest) throws -> RatingGoal {
        if let rating = request.rating, !(400...3200).contains(rating) {
            throw APIError.server(status: 400, code: "invalid_request", message: "Pick a goal between 400 and 3,200.")
        }
        let goal = RatingGoal(rating: request.rating, timeClass: request.rating == nil ? nil : request.timeClass)
        withState { state in
            state.goal = request.rating == nil ? nil : goal
            state.goalCleared = request.rating == nil
        }
        return goal
    }

    /// The fixture's goal, with what the player set or cleared since.
    private func goal(_ base: HomeProgress.Goal?, state: State) -> HomeProgress.Goal? {
        guard let base else { return nil }
        if state.goalCleared {
            return HomeProgress.Goal(
                timeClass: base.timeClass, set: false, suggested: base.suggested, summary: nil, samples: base.samples
            )
        }
        guard let set = state.goal, let rating = set.rating else { return base }
        let current = base.samples.last?.rating ?? base.suggested
        let distance = max(0, rating - current)
        let summary = HomeProgress.Goal.Summary(
            current: current, goal: rating, distance: distance, delta30: base.summary?.delta30,
            paceLine: distance > 0 ? base.summary?.paceLine : nil, reached: distance == 0
        )
        return HomeProgress.Goal(
            timeClass: set.timeClass ?? base.timeClass, set: true, suggested: base.suggested,
            summary: summary, samples: base.samples
        )
    }

    func completeOnboarding() throws {
        withState { $0.welcomeAnswered = true }
    }

    func dismissFirstReport() throws {
        withState { $0.firstReportDismissed = true }
    }

    // MARK: Settings

    func settings() throws -> AccountSettings {
        try withState { state in
            if let settings = state.settings { return settings }
            let settings: AccountSettings = try Self.load("player-settings")
            state.settings = settings
            return settings
        }
    }

    func updateSettings(_ request: UpdateSettingsRequest) throws -> AccountSettings {
        if let name = request.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw APIError.server(status: 422, code: "request_failed", message: "Enter your name.")
        }
        var settings = try settings()
        if let name = request.name { settings.profile.name = name.trimmingCharacters(in: .whitespaces) }
        if let theme = request.boardTheme {
            settings.board.theme = theme
            settings.board.saved = true
        }
        if let sound = request.boardSound { settings.board.sound = sound }
        if let lines = request.preferences?.newLinesPerDay { settings.preferences.newLinesPerDay = lines }
        if let auto = request.preferences?.autoReview { settings.preferences.autoReview = auto }
        for index in settings.emailConsents.indices {
            switch settings.emailConsents[index].type.value {
            case .marketing: if let on = request.emailConsents?.marketing { settings.emailConsents[index].on = on }
            case .newsletter: if let on = request.emailConsents?.newsletter { settings.emailConsents[index].on = on }
            case nil: break
            }
        }
        withState { $0.settings = settings }
        return settings
    }

    func setPrimaryRating(source: String, format: String) throws -> AccountRatings {
        var settings = try settings()
        guard let rating = settings.ratings.available.first(where: { $0.source.raw == source && $0.format == format }) else {
            throw APIError.server(status: 422, code: "request_failed", message: "This account has no such rating.")
        }
        settings.ratings = AccountRatings(primary: rating, available: settings.ratings.available)
        withState { $0.settings = settings }
        return settings.ratings
    }

    #if DEBUG
        /// `-CDFixturePlayer YES`: Debug builds on sample data start signed in
        /// as the fixture player. `-CDFixtureWelcome YES` also makes the home
        /// ask "Where do you play?" first.
        static let atLaunch: FixturePlayer? = {
            guard UserDefaults.standard.bool(forKey: "CDFixturePlayer") else { return nil }
            return FixturePlayer(welcome: UserDefaults.standard.bool(forKey: "CDFixtureWelcome"))
        }()
    #endif
}
