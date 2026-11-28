import ChessCore
import Foundation

/// The sample player: a signed-in player for the fixture client, so every
/// screen that needs an account runs offline in previews, tests and
/// screenshots. One player, the same everywhere: Sam Rivera, `quietrook` on
/// Lichess and Chess.com, around 1340 in blitz, who opens with the Italian
/// as White (the repertoire of `FixtureOpenings`), answers 1.e4 with the
/// Caro-Kann (the course they follow) and has 52 games in. The home, the
/// games list, the explorer, the repertoire's games check, the mistakes and
/// the Daily 5 all speak of those same games.
///
/// SYNTHETIC DATA. The `player-*.json` files in `Fixtures/api-v1` were written
/// by hand from the contract's schemas, not captured from a server: there is
/// no production test account. Names, games, ratings and positions are
/// invented; the positions are checked legal by `HomeFixtureTests`.
///
/// It keeps what the player changes (the Daily 5 done, settings, the goal,
/// the onboarding answered, a repertoire edited or trained) for the life of
/// the client, like a server would.
nonisolated final class FixturePlayer: @unchecked Sendable {
    /// The token of the debug launch option; any token works with the fixture client.
    static let token = "fixture-player"

    /// The repertoires and the explorer of the player's games.
    let openings: FixtureOpenings
    /// The player's games, newest first.
    let sampleGames: [FixtureGame]
    private let premium: Bool

    private struct State {
        var dailyDone = false
        var welcomeAnswered: Bool
        var firstReportDismissed = false
        var reminderOffered = false
        var goal: RatingGoal?
        var goalCleared = false
        var settings: AccountSettings?
        var accounts: [LinkedAccount]
        var courseReviewed = false
        var starred: [String: Bool] = [:]
        var reviewed: Set<String> = []
        /// The puzzle rating of `player-home.json`, moved by each rated puzzle.
        var puzzleRating = 1388
        var puzzleAttempts = 14
        var puzzlesSolved = 9
        var servedPuzzle: String?
        var seenPuzzles: Set<String> = []
    }

    private let lock = NSLock()
    private var state: State

    /// `welcome`: the player has no linked account yet, and the home asks
    /// "Where do you play?" until it is answered or skipped. `premium`: the
    /// player has Premium, everywhere.
    init(welcome: Bool = false, premium: Bool = false) {
        let lichess = LinkedAccount(
            provider: .lichess, username: FixtureData.handle, lastSyncedAt: .now.addingTimeInterval(-3600),
            historyComplete: true, ratings: ["blitz": 1342, "rapid": 1415]
        )
        let chesscom = LinkedAccount(
            provider: .chesscom, username: FixtureData.handle, lastSyncedAt: .now.addingTimeInterval(-3600),
            historyComplete: true, ratings: ["blitz": 1318, "rapid": 1392]
        )
        let games = FixtureData.games()
        sampleGames = games
        openings = FixtureOpenings(premium: premium, games: games)
        self.premium = premium
        state = State(welcomeAnswered: !welcome, accounts: welcome ? [] : [lichess, chesscom])
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

    func me() throws -> Me {
        let me: Me = try Self.load("player-me")
        guard premium else { return me }
        let access = Me.Access(premium: true, paid: true, viaCoachPlan: false, viaAppStore: false, trial: me.access.trial)
        return Me(user: me.user, hasPassword: me.hasPassword, access: access, freeLimits: me.freeLimits)
    }

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

    // MARK: Games

    private static let pageSize = 30

    /// The games, newest first, a page at a time; the cursor is where the next page starts.
    func games(cursor: String? = nil) throws -> GamesPage {
        let start = cursor.flatMap(Int.init) ?? 0
        let (starred, reviewed) = withState { ($0.starred, $0.reviewed) }
        let page = sampleGames.dropFirst(start).prefix(Self.pageSize).map { game in
            Self.summary(game.summary, starred: starred[game.summary.id], reviewed: reviewed.contains(game.summary.id))
        }
        let next = start + Self.pageSize
        return GamesPage(games: Array(page), nextCursor: next < sampleGames.count ? String(next) : nil)
    }

    func game(id: String) throws -> GameDetail {
        guard let game = sampleGames.first(where: { $0.summary.id == id }) else {
            throw APIError.server(status: 404, code: "not_found", message: "Game not found.")
        }
        let detail = game.detail
        let (starred, reviewed) = withState { ($0.starred[id], $0.reviewed.contains(id)) }
        return GameDetail(
            id: detail.id, source: detail.source, white: detail.white, black: detail.black, whiteElo: detail.whiteElo,
            blackElo: detail.blackElo, result: detail.result, timeClass: detail.timeClass, opening: detail.opening,
            userColor: detail.userColor, playedAt: detail.playedAt, ply: detail.ply, starred: starred ?? detail.starred,
            reviewed: reviewed || detail.reviewed, pgn: detail.pgn, url: nil, review: nil
        )
    }

    func setStar(game: String, starred: Bool) { withState { $0.starred[game] = starred } }
    func noteReviewed(game: String) { withState { _ = $0.reviewed.insert(game) } }

    private static func summary(_ game: GameSummary, starred: Bool?, reviewed: Bool) -> GameSummary {
        GameSummary(
            id: game.id, source: game.source, white: game.white, black: game.black, whiteElo: game.whiteElo,
            blackElo: game.blackElo, result: game.result, timeClass: game.timeClass, timeControl: game.timeControl,
            eco: game.eco, opening: game.opening, userColor: game.userColor, playedAt: game.playedAt, ply: game.ply,
            rated: game.rated, starred: starred ?? game.starred, reviewed: reviewed || game.reviewed
        )
    }

    func mistakes() throws -> MistakeQueue { try Self.load("player-mistakes") }

    // MARK: The course the player follows

    /// The Caro-Kann Bunker: its free line is learned, and some of its moves
    /// are due again until they are reviewed.
    static let courseSlug = "practical-caro-kann"
    static let courseDeck = "course:\(courseSlug)"
    /// The steps of the free line asked again in the review.
    private static let courseDueSteps = [21, 23, 25, 27]

    private var courseProgress: DeckProgress {
        let due = !withState { $0.courseReviewed }
        return DeckProgress(
            lines: 1, learned: 1, newLines: 0, dueLines: due ? 1 : 0, solidLines: due ? 0 : 1,
            dueMoves: due ? Self.courseDueSteps.count : 0, moves: 14
        )
    }

    /// The catalogue as this player sees it: one course followed.
    func courses(_ cards: [CourseCard]) -> [CourseCard] {
        cards.map { card in
            guard card.slug == Self.courseSlug else { return card }
            return CourseCard(
                slug: card.slug, title: card.title, color: card.color, style: card.style, level: card.level,
                description: card.description, totals: card.totals, previewFen: card.previewFen,
                previewMove: card.previewMove, freeLineId: card.freeLineId, voiced: card.voiced, enrollment: .active,
                progress: courseProgress
            )
        }
    }

    func course(_ course: CourseDetail) -> CourseDetail {
        guard course.slug == Self.courseSlug else { return course }
        let progress = courseProgress
        let chapters = course.chapters.map { chapter in
            CourseDetail.Chapter(title: chapter.title, intro: chapter.intro, lines: chapter.lines.map { line in
                guard line.id == course.freeLineId else { return line }
                return .init(id: line.id, label: line.label, moves: line.moves, state: progress.dueLines > 0 ? .due : .solid, free: line.free)
            })
        }
        return CourseDetail(
            slug: course.slug, title: course.title, color: course.color, style: course.style, level: course.level,
            description: course.description, totals: course.totals, previewFen: course.previewFen,
            previewMove: course.previewMove, freeLineId: course.freeLineId, voiced: course.voiced, enrollment: .active,
            intro: course.intro, deck: course.deck, progress: progress, chapters: chapters, pace: course.pace,
            freeLearned: true, narration: course.narration
        )
    }

    /// The review of the course, from its Learn session: the due moves of the free line.
    func courseReview(from learn: CourseSession) -> CourseSession {
        let due = !withState { $0.courseReviewed }
        let line = learn.lines.first { $0.id == learn.learn.first } ?? learn.lines.first
        let tested = line.map { line in Self.courseDueSteps.filter { $0 < line.steps.count && line.steps[$0].mine } } ?? []
        let review = due ? line.map { [CourseSession.ReviewItem(lineId: $0.id, test: tested)] } ?? [] : []
        return CourseSession(
            deck: learn.deck, mode: .review, color: learn.color, lines: review.isEmpty ? [] : learn.lines, learn: [],
            review: review, known: line?.steps.filter(\.mine).map(\.key) ?? [], next: nil,
            chapterTitles: learn.chapterTitles, narration: learn.narration
        )
    }

    func recordCourseGrades() { withState { $0.courseReviewed = true } }

    /// `GET /training/due`: the course and the repertoires, the deck with the most due moves on top.
    func due(courseTitle: String) async -> DueSummary {
        let course = DueSummary.Deck(
            deck: Self.courseDeck, kind: "course", name: courseTitle, color: "BLACK", progress: courseProgress
        )
        let decks = ([course] + (await openings.dueDecks())).filter { $0.progress.moves > 0 }
        let total = decks.reduce(0) { $0 + $1.progress.dueMoves }
        let top = decks.filter { $0.progress.dueMoves > 0 }.max { $0.progress.dueMoves < $1.progress.dueMoves }
        return DueSummary(totalDue: total, decks: decks, top: top?.deck, learnNext: nil)
    }

    // MARK: Puzzles

    func puzzlePlayer(now: Date = .now) -> PuzzlePlayer {
        let state = withState { $0 }
        // A curve that ends on the rating: the last attempts, a few days apart.
        let steps = [-52, -44, -51, -38, -30, -36, -22, -27, -14, -8, -15, 0]
        let history = steps.enumerated().map { index, offset in
            PuzzlePlayer.Point(
                at: now.addingTimeInterval(-Double(steps.count - 1 - index) * 1.5 * 86400), rating: state.puzzleRating + offset,
                solved: index == 0 || offset > steps[index - 1]
            )
        }
        return PuzzlePlayer(
            rating: state.puzzleRating, deviation: 62, solved: state.puzzlesSolved, attempts: state.puzzleAttempts,
            last30Days: .init(attempts: state.puzzleAttempts, solved: state.puzzlesSolved), history: history
        )
    }

    /// The puzzle of the free set nearest the player's rating that was not served yet.
    func nextPuzzle(theme: String?, from puzzles: [Puzzle]) throws -> Puzzle {
        let themed = puzzles.filter { puzzle in theme == nil || puzzle.themes.contains { $0.id == theme } }
        return try withState { state in
            let fresh = themed.filter { !state.seenPuzzles.contains($0.id) }
            let pool = fresh.isEmpty ? themed : fresh
            guard let next = pool.min(by: { abs($0.rating - state.puzzleRating) < abs($1.rating - state.puzzleRating) }) else {
                throw APIError.server(status: 404, code: "not_found", message: "No puzzle with this theme.")
            }
            if fresh.isEmpty { state.seenPuzzles = [] }
            state.seenPuzzles.insert(next.id)
            state.servedPuzzle = next.id
            return next
        }
    }

    /// Once per served puzzle, as the server takes it.
    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool) throws -> PuzzleAttempt {
        try withState { state in
            guard state.servedPuzzle == puzzleId else {
                throw APIError.server(status: 409, code: "request_failed", message: "This puzzle is no longer the one being solved.")
            }
            state.servedPuzzle = nil
            let delta = solved ? 8 : -8
            state.puzzleRating += delta
            state.puzzleAttempts += 1
            if solved { state.puzzlesSolved += 1 }
            return PuzzleAttempt(rating: state.puzzleRating, delta: delta, deviation: 62, solved: state.puzzlesSolved)
        }
    }

    /// Woodpecker asks for a settled puzzle rating first; the sample data
    /// holds no sets, so building one is refused in its own words.
    static let woodpeckerCalibration = 20
    static let noWoodpeckerSets = APIError.server(
        status: 422, code: "request_failed",
        message: "Sample data holds no Woodpecker sets. Switch to a server in Developer settings to build one."
    )

    func woodpecker(themeGroups: [PuzzleThemeGroup]) -> WoodpeckerOverview {
        let attempts = withState { $0.puzzleAttempts }
        let calibrated = attempts >= Self.woodpeckerCalibration
        return WoodpeckerOverview(
            state: !calibrated ? .calibrate : premium ? .create : .discovery, premium: premium,
            calibration: .init(attempts: attempts, required: Self.woodpeckerCalibration, calibrated: calibrated),
            discovery: .init(used: false, size: 30, cycles: 2), completedSets: 0,
            creation: .init(sizes: .init(min: 30, max: 300, default: 100, presets: [50, 100, 200]), themeGroups: themeGroups),
            run: nil, history: []
        )
    }

    // MARK: Home

    func home() throws -> PlayerHome {
        var home: PlayerHome = try Self.load("player-home")
        let state = withState { $0 }
        home.puzzleRating = Double(state.puzzleRating)
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
        if state.welcomeAnswered { home.totalGames = sampleGames.count }
        let homeGoal = goal(home.progress?.goal, state: state)
        home.progress?.goal = homeGoal
        return home
    }

    /// The home with the step of the opening lines due, as the server plans
    /// it (`lib/player/today.ts`): after the mistakes, five steps at most.
    func home(due: DueSummary) throws -> PlayerHome {
        var home = try home()
        guard due.totalDue > 0, !home.onboarding.needsWelcome else { return home }
        let step = TodayStep(
            key: "repertoire", title: "Repeat your opening lines",
            detail: "\(due.totalDue) \(due.totalDue == 1 ? "move is" : "moves are") due for spaced repetition",
            minutes: max(2, min(15, Int((Double(due.totalDue) * 0.5).rounded(.up)))), cta: "Train lines", primary: false,
            target: .init(kind: .init(.deck), gameId: nil, slug: nil, deck: due.top, assignmentId: nil)
        )
        let index = home.today.firstIndex { $0.target.kind.value == .puzzles } ?? home.today.count
        home.today.insert(step, at: index)
        home.today = Array(home.today.prefix(5))
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
        /// as the sample player; without it, sample data is a guest's.
        /// `-CDFixtureWelcome YES` also makes the home ask "Where do you
        /// play?" first; `-CDFixturePremium YES` gives the player Premium.
        static let atLaunch: FixturePlayer? = {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "CDFixturePlayer") else { return nil }
            return FixturePlayer(welcome: defaults.bool(forKey: "CDFixtureWelcome"), premium: defaults.bool(forKey: "CDFixturePremium"))
        }()
    #endif
}
