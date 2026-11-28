import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// The signed-in player's home, Daily 5 and settings. Everything here runs
// against stubs and the synthetic fixture player: no real account exists to
// exercise these routes against the server.

/// A server for the home tests: the fixture player for what is read, and a
/// log of what the app sent, with failures on demand.
private final class HomeServer: ChessDeskAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var updates: [UpdateSettingsRequest] = []
    private var completions: [DailyCompletionRequest] = []
    private var starts: [DailySessionRequest] = []
    private var reminders: [ReminderRequest] = []
    private let fixture: FixtureAPI
    let player: FixturePlayer

    var failsUpdate = false
    var failsCompletion = 0
    var settingsAnswer: AccountSettings?
    var dailyAnswer: DailyPlan?

    init(player: FixturePlayer = FixturePlayer()) {
        self.player = player
        fixture = FixtureAPI(delay: .zero, player: player)
    }

    var log: [String] { lock.withLock { calls } }
    var sentUpdates: [UpdateSettingsRequest] { lock.withLock { updates } }
    var sentCompletions: [DailyCompletionRequest] { lock.withLock { completions } }
    var sentStarts: [DailySessionRequest] { lock.withLock { starts } }
    var sentReminders: [ReminderRequest] { lock.withLock { reminders } }
    private func note(_ call: String) { lock.withLock { calls.append(call) } }

    // The account and the courses, from the fixture.
    func login(email: String, password: String) async throws -> AuthSession { throw APIError.offline }
    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession { throw APIError.offline }
    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession { throw APIError.offline }
    func resendVerification(token: String) async throws {}
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {}
    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me { try player.me() }
    func refresh(token: String) async throws -> AuthSession { throw APIError.offline }
    func me(token: String) async throws -> Me { try player.me() }
    func courses(token: String?) async throws -> [CourseCard] { try await fixture.courses(token: token) }
    func course(slug: String, token: String?) async throws -> CourseDetail { try await fixture.course(slug: slug, token: token) }
    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        try await fixture.courseSession(slug: slug, mode: mode, line: line, token: token)
    }
    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws {}
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { 0 }
    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {}
    func due(token: String) async throws -> DueSummary { try await fixture.due(token: token) }
    func paths(token: String?) async throws -> [PathCard] { try await fixture.paths(token: token) }
    func path(slug: String, token: String?) async throws -> PathDetail { try await fixture.path(slug: slug, token: token) }
    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        try await fixture.pathSession(slug: slug, stage: stage, token: token)
    }
    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { 0 }

    func recordMistakeAttempt(_ mistake: String, result: MistakeResult, token: String) async throws -> MistakeAttempt {
        note("attempt \(mistake) \(result.rawValue)")
        return MistakeAttempt(intervalDays: 1)
    }

    // The home and the Daily 5.
    func home(token: String) async throws -> PlayerHome { try player.home() }
    func progress(token: String) async throws -> ProgressPage { try player.progress() }
    func daily(again: Bool, token: String) async throws -> DailyPlan {
        note("daily again=\(again)")
        return try dailyAnswer ?? player.daily(again: again)
    }
    func startDaily(_ request: DailySessionRequest, token: String) async throws -> DailySessionStart {
        lock.withLock { starts.append(request) }
        return try player.startDaily()
    }
    func completeDaily(_ request: DailyCompletionRequest, token: String) async throws -> DailyCompletion {
        lock.withLock { completions.append(request) }
        let fails = lock.withLock { () -> Bool in
            guard failsCompletion > 0 else { return false }
            failsCompletion -= 1
            return true
        }
        if fails { throw APIError.offline }
        return try player.completeDaily()
    }
    func setReminder(_ request: ReminderRequest, token: String) async throws -> DailyReminder {
        lock.withLock { reminders.append(request) }
        return try player.setReminder(request)
    }
    func dismissReminderOffer(token: String) async throws { note("dismiss reminder") }

    // The settings.
    func settings(token: String) async throws -> AccountSettings {
        note("settings")
        return try settingsAnswer ?? player.settings()
    }
    func updateSettings(_ request: UpdateSettingsRequest, token: String) async throws -> AccountSettings {
        lock.withLock { updates.append(request) }
        if failsUpdate {
            throw APIError.server(status: 422, code: "request_failed", message: "The server said no.")
        }
        return try player.updateSettings(request)
    }
    func setPrimaryRating(source: String, format: String, token: String) async throws -> AccountRatings {
        try player.setPrimaryRating(source: source, format: format)
    }
}

private func step(_ key: String, _ kind: String, primary: Bool = false, gameId: String? = nil, slug: String? = nil, deck: String? = nil) -> TodayStep {
    TodayStep(
        key: key, title: key, detail: "", minutes: 5, cta: "Go", primary: primary,
        target: .init(kind: .init(raw: kind), gameId: gameId, slug: slug, deck: deck, assignmentId: nil)
    )
}

private func target(_ kind: String, gameId: String? = nil, slug: String? = nil, deck: String? = nil) -> TodayStep.Target {
    step("k", kind, gameId: gameId, slug: slug, deck: deck).target
}

// MARK: Decoding

@Suite struct HomeDecodingTests {
    @Test func unknownValuesAreKeptAsTextAndNotRead() throws {
        let data = Data(#"{"kind":"woodpecker","gameId":null,"slug":null,"deck":null,"assignmentId":null}"#.utf8)
        let decoded = try APICoding.decoder.decode(TodayStep.Target.self, from: data)
        #expect(decoded.kind.raw == "woodpecker")
        #expect(decoded.kind.value == nil)
        let encoded = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(decoded)) as? [String: Any]
        #expect(encoded?["kind"] as? String == "woodpecker")
    }

    @Test func clearingTheGoalSendsANullRating() throws {
        let object = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(RatingGoalRequest(rating: nil, timeClass: nil)))
        let body = try #require(object as? [String: Any])
        #expect(body.keys.contains("rating"))
        #expect(body["rating"] is NSNull)
        #expect(body["timeClass"] == nil)
    }

    @Test func aSettingsChangeSendsOnlyWhatChanged() throws {
        let request = UpdateSettingsRequest(preferences: .init(autoReview: false))
        let object = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(request))
        let body = try #require(object as? [String: Any])
        #expect(Set(body.keys) == ["preferences"])
        #expect((body["preferences"] as? [String: Any])?.keys.sorted() == ["autoReview"])
    }
}

/// The synthetic fixtures decode, and their positions are real chess.
@Suite struct HomeFixtureTests {
    private let player = FixturePlayer()

    @Test func everyFixtureDecodes() throws {
        _ = try player.me()
        _ = try player.games()
        _ = try player.game(id: "sample-game-1")
        _ = try player.mistakes()
        _ = try player.settings()
        _ = try player.patternDrill(key: "hanging")
        let home = try player.home()
        #expect(home.today.map(\.key) == ["daily", "review", "path", "mistakes", "puzzles"])
        #expect(try player.progress().calendar.count == 84)
        #expect(try player.daily(again: false).items.count == 5)
    }

    @Test func everyPositionIsLegalAndItsMoveIsNamedRight() throws {
        let items = try player.daily(again: false).items
        let mistakes = try player.mistakes().due + player.patternDrill(key: "hanging").mistakes
        let positions = items.map { ($0.fen, $0.bestUci, $0.bestSan) } + mistakes.map { ($0.fen, $0.bestUci, $0.bestSan) }
        for (fen, uci, san) in positions {
            let position = try #require(Position(fen: fen), "\(fen) reads")
            let move = try #require(Move(uci: uci))
            #expect(position.playing(move) != nil, "\(uci) is legal in \(fen)")
            #expect(position.san(for: move) == san, "\(uci) is \(san) in \(fen)")
        }
    }

    @Test func theFixtureGameReplays() throws {
        let game = try player.game(id: "sample-game-1")
        let line = GameLine(pgn: game.pgn)
        #expect(line.moves.count == 26)
        #expect(line.moves.count == game.ply)
        #expect(line.headers["White"] == "quietrook")
        #expect(line.headers["Black"] == "marta_k")
    }

    @Test func theDailyFiveMovesTheStreakOnceADay() throws {
        let player = FixturePlayer()
        let first = try player.completeDaily()
        let second = try player.completeDaily()
        #expect(first.counted && first.streak == 5)
        #expect(!second.counted && second.streak == 5)
        let home = try player.home()
        #expect(home.daily.doneToday)
        #expect(!home.today.contains { $0.key == "daily" })
        #expect(home.today.first?.primary == true)
    }
}

// MARK: The plan

@Suite struct HomeRouterTests {
    @Test func everyKindOfTheContractIsRouted() {
        #expect(HomeRouter.route(target("daily")) == .daily)
        #expect(HomeRouter.route(target("review", gameId: "g1")) == .game(id: "g1"))
        #expect(HomeRouter.route(target("review")) == nil)
        #expect(HomeRouter.route(target("path", slug: "reach-1000-elo")) == .path(slug: "reach-1000-elo"))
        #expect(HomeRouter.route(target("path")) == nil)
        #expect(HomeRouter.route(target("course", slug: "practical-caro-kann")) == .course(slug: "practical-caro-kann"))
        #expect(HomeRouter.route(target("course")) == .courses)
        #expect(HomeRouter.route(target("courses")) == .courses)
        #expect(HomeRouter.route(target("mistakes")) == .mistakes)
        #expect(HomeRouter.route(target("deck", deck: "course:aggressive-1e4")) == .courseReview(slug: "aggressive-1e4"))
        #expect(HomeRouter.route(target("deck", deck: "course:")) == nil)
        #expect(HomeRouter.route(target("deck", deck: "repertoire:")) == nil)
        #expect(HomeRouter.route(target("deck", deck: "repertoire:r1")) == .repertoire(id: "r1"))
        #expect(HomeRouter.route(target("deck")) == .repertoires)
        #expect(HomeRouter.route(target("deck", deck: "study:s1")) == nil)
        #expect(HomeRouter.route(target("puzzles")) == .puzzles)
        #expect(HomeRouter.route(target("play")) == .play)
        #expect(HomeRouter.route(target("coach")) == nil)
        #expect(HomeRouter.route(target("tournament")) == nil)
    }

    /// Every kind the contract lists has a case here: a new one fails this test.
    @Test func theContractListsNoKindTheRouterDoesNotKnow() throws {
        let bundle = Bundle(for: HomeTestsBundleToken.self)
        let url = try #require(bundle.url(forResource: "openapi-v1", withExtension: "json", subdirectory: "contracts"))
        let contract = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let schemas = try #require((contract["components"] as? [String: Any])?["schemas"] as? [String: Any])
        let step = try #require(schemas["TodayStep"] as? [String: Any])
        let properties = try #require(step["properties"] as? [String: Any])
        let targetSchema = try #require((properties["target"] as? [String: Any])?["properties"] as? [String: Any])
        let kinds = try #require((targetSchema["kind"] as? [String: Any])?["enum"] as? [String])
        for kind in kinds { #expect(TodayStep.Kind(rawValue: kind) != nil, "\(kind) is known") }
    }

    /// Every step the app has a screen for shows, in the server's order; a
    /// coach's assignment and a kind added on the site later are dropped.
    @Test func thePlanKeepsTheServersOrderAndDropsWhatCannotOpen() {
        let steps = [
            step("coach", "coach", primary: true),
            step("daily", "daily"),
            step("later", "added-on-the-site-later"),
            step("review", "review", gameId: "g1"),
            step("puzzles", "puzzles"),
            step("repertoire", "deck", deck: "repertoire:r1"),
            step("course", "deck", deck: "course:practical-caro-kann"),
            step("lines", "deck"),
            step("play", "play"),
        ]
        let plan = HomeRouter.plan(steps)
        #expect(plan.map(\.step.key) == ["daily", "review", "puzzles", "repertoire", "course", "lines", "play"])
        #expect(plan.map(\.route) == [
            .daily, .game(id: "g1"), .puzzles, .repertoire(id: "r1"), .courseReview(slug: "practical-caro-kann"),
            .repertoires, .play,
        ])
        // The coach's step led; the first step shown leads instead.
        #expect(plan.map(\.leads) == [true, false, false, false, false, false, false])
    }

    /// Where each destination goes: a trainer over the app, a section, or a
    /// screen pushed on Today.
    @Test @MainActor func everyDestinationOpensSomewhere() {
        let app = AppNavigator()
        let home = HomeNavigator(app: app)
        let covers: [(HomeRoute, HomeCover)] = [
            (.daily, .daily), (.mistakes, .mistakes), (.patternDrill(key: "hanging"), .patternDrill(key: "hanging")),
            (.repertoire(id: "r1"), .repertoireReview(id: "r1")), (.courseReview(slug: "c1"), .courseReview(slug: "c1")),
        ]
        for (route, cover) in covers {
            home.open(route)
            #expect(home.cover == cover)
            #expect(app.section == .today)
            home.closeCover()
            #expect(home.cover == nil)
        }
        #expect(home.revision == covers.count)

        home.open(.courses)
        #expect(app.section == .learn && app.learn.isEmpty)
        home.open(.repertoires)
        #expect(app.section == .learn && app.learn.count == 1)
        home.open(.play)
        #expect(app.section == .play && app.play.isEmpty)
        home.open(.puzzles)
        #expect(app.section == .train && app.train.count == 1)
        home.open(.games)
        #expect(app.section == .games && app.games.isEmpty)

        // A game, a path, a course and Progress are pushed on Today, over what is there.
        home.open(.game(id: "g1"))
        #expect(app.section == .today && app.today.count == 1)
        home.open(.progress)
        home.open(.path(slug: "reach-1000-elo"))
        home.open(.course(slug: "practical-caro-kann"))
        #expect(app.today.count == 4)
        #expect(home.cover == nil)
    }

    @Test func thePatternsLeadToTheirDrillTheirGameOrTheGames() throws {
        let patterns = try FixturePlayer().progress().progress.patterns
        #expect(patterns.map { PatternRows.route($0) } == [.patternDrill(key: "hanging"), .game(id: "sample-game-1"), .games])
    }
}

// MARK: Daily 5

@MainActor
@Suite struct DailySessionTests {
    private func model(_ server: HomeServer, hour: Int = 18) -> DailySessionModel {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "Europe/Paris").unsafelyUnwrapped
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: hour)).unsafelyUnwrapped
        return DailySessionModel(api: server, token: "t", timeZone: zone, now: now)
    }

    private func expected(_ model: DailySessionModel) -> Move { model.drill.expected.unsafelyUnwrapped }

    /// A legal move of the position that is not the expected one.
    private func wrong(_ model: DailySessionModel) -> Move {
        let start = model.drill.start.unsafelyUnwrapped
        return start.legalMoves().first { start.normalized($0) != expected(model) }.unsafelyUnwrapped
    }

    @Test func aSessionGoesFromTheFirstPositionToTheStreak() async throws {
        let server = HomeServer()
        let model = model(server)
        await model.load()
        #expect(model.phase == .solving)
        #expect(server.sentStarts.map(\.total) == [5])
        #expect(server.sentStarts.first?.tz == "Europe/Paris")
        #expect(server.sentStarts.first?.source == .mistakes)

        // 1: a wrong move first, then the move: missed.
        #expect(model.play(wrong(model)) == .wrong)
        #expect(model.drill.feedback == .wrong)
        #expect(model.play(expected(model)) == .resolved(.missed))
        await model.pending?.value
        // Nothing more happens on a resolved position.
        #expect(model.play(expected(model)) == .ignored)
        model.drill.next()
        // 2: shown, then played: revealed.
        model.drill.reveal()
        #expect(model.play(expected(model)) == .resolved(.revealed))
        await model.pending?.value
        // 3 to 5: found at once.
        for _ in 0..<3 {
            model.drill.next()
            #expect(model.play(expected(model)) == .resolved(.solved))
            await model.pending?.value
        }
        #expect(model.drill.isComplete)
        #expect(server.log.filter { $0.hasPrefix("attempt") } == [
            "attempt m-1 missed", "attempt m-2 revealed", "attempt m-3 solved", "attempt m-4 solved", "attempt m-5 solved",
        ])
        #expect(server.sentCompletions.map(\.solved) == [3])
        #expect(server.sentCompletions.map(\.total) == [5])
        guard case let .finished(result) = model.phase else {
            Issue.record("the session is closed, not \(model.phase)")
            return
        }
        #expect(result.counted && result.streak == 5)
        // The server asked to offer a reminder, at the hour the session ended.
        #expect(model.reminderOffer == .offered)
        await model.acceptReminder()
        #expect(model.reminderOffer == .set(hour: 18))
        #expect(server.sentReminders.map(\.channel) == [.email])
        #expect(server.sentReminders.first?.hour == 18)
    }

    @Test func aSessionThatCannotBeClosedSaysSoAndTriesAgain() async throws {
        let server = HomeServer()
        server.failsCompletion = 1
        let model = model(server)
        await model.load()
        for index in 0..<5 {
            if index > 0 { model.drill.next() }
            model.play(expected(model))
            await model.pending?.value
        }
        guard case .closeFailed = model.phase else {
            Issue.record("the failure is said, not \(model.phase)")
            return
        }
        await model.close()
        guard case let .finished(result) = model.phase else {
            Issue.record("the retry closes the session, not \(model.phase)")
            return
        }
        #expect(result.streak == 5)
        #expect(server.sentCompletions.count == 2)
    }

    @Test func aDayAlreadyDoneOffersFiveMore() async throws {
        let server = HomeServer()
        _ = try server.player.completeDaily()
        let model = model(server)
        await model.load()
        #expect(model.phase == .doneEarlier)
        #expect(model.streak?.doneToday == true)
        await model.load(again: true)
        #expect(model.phase == .solving)
        #expect(server.log.filter { $0.hasPrefix("daily") } == ["daily again=false", "daily again=true"])
    }

    @Test func nothingToSolveIsSaid() async throws {
        let server = HomeServer()
        var plan = try server.player.daily(again: false)
        plan.items = []
        plan.source = nil
        server.dailyAnswer = plan
        let model = model(server)
        await model.load()
        #expect(model.phase == .empty)
        #expect(server.sentStarts.isEmpty)
    }

    @Test func puzzlesAreNotRecordedAsMistakes() async throws {
        let server = HomeServer()
        var plan = try server.player.daily(again: false)
        let item = plan.items[0]
        plan.items = [TrainItem(
            id: "p-1", kind: .init(.puzzle), fen: item.fen, bestUci: item.bestUci, bestSan: item.bestSan,
            label: "Rated puzzle", classification: nil, moveLabel: nil, playedSan: nil, gameId: nil, firstTime: true
        )]
        plan.source = .init(.puzzles)
        server.dailyAnswer = plan
        let model = model(server)
        await model.load()
        model.play(expected(model))
        await model.pending?.value
        #expect(!server.log.contains { $0.hasPrefix("attempt") })
        #expect(server.sentCompletions.map(\.source) == [.puzzles])
    }

    @Test func declinedReminderIsToldToTheServer() async throws {
        let server = HomeServer()
        let model = model(server)
        await model.load()
        for index in 0..<5 {
            if index > 0 { model.drill.next() }
            model.play(expected(model))
            await model.pending?.value
        }
        await model.dismissReminder()
        #expect(model.reminderOffer == .dismissed)
        #expect(server.log.contains("dismiss reminder"))
    }
}

// MARK: Settings

@MainActor
@Suite struct SettingsSyncTests {
    private func preferences() -> BoardPreferences {
        let defaults = UserDefaults(suiteName: "home-tests-\(UUID().uuidString)").unsafelyUnwrapped
        return BoardPreferences(defaults: defaults)
    }

    private func account(theme: BoardPreferences.Theme, saved: Bool = true) throws -> AccountSettings {
        var settings = try FixturePlayer().settings()
        settings.board.theme = theme
        settings.board.saved = saved
        settings.board.sound = .init(enabled: false, volume: 0.8)
        return settings
    }

    private let green = BoardPreferences.Theme(
        pieceSet: "kaneo", boardTexture: "wood", lightSquare: "#eeeed2", darkSquare: "#769656"
    )

    @Test func signedInTheBoardIsTheAccounts() async throws {
        let server = HomeServer()
        server.settingsAnswer = try account(theme: green)
        let preferences = preferences()
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: "t")
        #expect(model.phase == .ready)
        #expect(preferences.theme == green)
        #expect(preferences.sound == .init(enabled: false, volume: 0.8))
        // Applying the account's board writes nothing back.
        model.boardChanged()
        await model.settleBoard()
        #expect(server.sentUpdates.isEmpty)
    }

    @Test func aChangeOnTheDeviceIsWrittenToTheAccount() async throws {
        let server = HomeServer()
        let preferences = preferences()
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: "t")
        preferences.pieceSet = .fantasy
        model.boardChanged()
        await model.settleBoard()
        #expect(server.sentUpdates.count == 1)
        #expect(server.sentUpdates.first?.boardTheme?.pieceSet == "fantasy")
        #expect(server.sentUpdates.first?.boardSound == nil)
        #expect(model.settings?.board.theme.pieceSet == "fantasy")
        #expect(model.notice == nil)
    }

    @Test func aRefusedWriteIsUndoneAndSaid() async throws {
        let server = HomeServer()
        let preferences = preferences()
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: "t")
        let before = preferences.theme
        server.failsUpdate = true
        preferences.squareColors = .green
        model.boardChanged()
        await model.settleBoard()
        #expect(preferences.theme == before)
        #expect(model.notice?.isError == true)
        #expect(model.notice?.text.contains("The server said no.") == true)

        await model.setName("Samantha")
        #expect(model.settings?.profile.name == "Sam Rivera")
        await model.setAutoReview(false)
        #expect(model.settings?.preferences.autoReview == true)
    }

    @Test func aGuestKeepsTheBoardOnTheDevice() async throws {
        let server = HomeServer()
        let preferences = preferences()
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: nil)
        preferences.texture = .wood
        model.boardChanged()
        await model.settleBoard()
        #expect(model.phase == .guest)
        #expect(server.log.isEmpty)
        #expect(server.sentUpdates.isEmpty)
        #expect(preferences.texture == .wood)
    }

    @Test func signingOutStopsTheSync() async throws {
        let server = HomeServer()
        let preferences = preferences()
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: "t")
        await model.attach(api: server, token: nil)
        preferences.pieceSet = .spatial
        model.boardChanged()
        await model.settleBoard()
        #expect(model.settings == nil)
        #expect(server.sentUpdates.isEmpty)
    }

    @Test func anAccountWithoutABoardTakesTheOneOfTheDevice() async throws {
        let server = HomeServer()
        server.settingsAnswer = try account(theme: .standard, saved: false)
        let preferences = preferences()
        preferences.theme = green
        let model = AccountSettingsModel(preferences: preferences, boardDelay: .zero)
        await model.attach(api: server, token: "t")
        #expect(preferences.theme == green)
        #expect(server.sentUpdates.first?.boardTheme == green)
    }

    @Test func profileTrainingAndEmailsAreSaved() async throws {
        let server = HomeServer()
        let model = AccountSettingsModel(preferences: preferences(), boardDelay: .zero)
        await model.attach(api: server, token: "t")
        await model.setName("  Sam R.  ")
        await model.setNewLinesPerDay(10)
        await model.setEmailConsent(.newsletter, on: false)
        #expect(server.sentUpdates.map(\.name) == ["Sam R.", nil, nil])
        #expect(server.sentUpdates[1].preferences?.newLinesPerDay == 10)
        #expect(server.sentUpdates[2].emailConsents?.newsletter == false)
        #expect(server.sentUpdates[2].emailConsents?.marketing == nil)
        #expect(model.settings?.profile.name == "Sam R.")
        #expect(model.settings?.preferences.newLinesPerDay == 10)
        #expect(model.settings?.emailConsents.first { $0.type.value == .newsletter }?.on == false)

        let rapid = try #require(model.settings?.ratings.available.first { $0.format == "rapid" })
        await model.setPrimaryRating(rapid)
        #expect(model.settings?.ratings.primary?.format == "rapid")

        await model.setReminder(channel: .email, hour: 7)
        #expect(model.settings?.reminder.channel.value == .email)
        #expect(model.settings?.reminder.hour == 7)
        await model.setReminder(channel: .off, hour: 7)
        #expect(server.sentReminders.last?.hour == nil)
    }
}

private final class HomeTestsBundleToken {}
