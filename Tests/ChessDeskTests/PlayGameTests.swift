import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// Playing the bots: the catalogue, a whole game with a stub engine (win,
// loss, draw, resignation, a game restored after a relaunch), and the
// wording of results. Expectations ported from the site name their file.

/// A server that keeps bot games, in memory. Everything else is sample data.
private final class PlayServer: ChessDeskAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SaveBotGameRequest] = []
    private var failures: Int
    private var unreachable: Bool
    private var asked: [String?] = []
    private let guest = FixtureAPI(delay: .zero)

    init(failingSaves: Int = 0, catalogueFails: Bool = false) {
        failures = failingSaves
        unreachable = catalogueFails
    }

    var saved: [SaveBotGameRequest] { lock.withLock { stored } }
    /// The token of every catalogue request, in order.
    var catalogueTokens: [String?] { lock.withLock { asked } }
    /// Cuts or restores the connection for the catalogue.
    var catalogueFails: Bool {
        get { lock.withLock { unreachable } }
        set { lock.withLock { unreachable = newValue } }
    }

    var savesBotGames: Bool { true }

    /// The captured catalogue, with `canSaveGames` as the server sets it:
    /// true for a session, false for a visitor.
    func playBots(token: String?) async throws -> PlayCatalogue {
        lock.withLock { asked.append(token) }
        if catalogueFails { throw APIError.offline }
        var object = try #require(JSONSerialization.jsonObject(with: FixtureAPI.data("play-bots")) as? [String: Any])
        object["canSaveGames"] = token != nil
        return try LiveAPI.decode(status: 200, data: JSONSerialization.data(withJSONObject: object))
    }

    /// Answers as `POST /api/v1/play/games` does: the saved game, in the
    /// shape of `GET /api/v1/games/{gameId}`, the opponent named from the
    /// catalogue and the half-moves counted from the PGN.
    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail {
        let count: Int? = lock.withLock {
            if failures > 0 {
                failures -= 1
                return nil
            }
            stored.append(game)
            return stored.count
        }
        guard let count else { throw APIError.offline }
        let catalogue = try FixtureAPI.playCatalogue()
        let bot = catalogue.bots.first { $0.id == game.bot }
        guard let name = bot?.name ?? (game.bot == catalogue.custom.id ? catalogue.custom.name : nil),
              let rating = bot?.rating ?? game.rating
        else { throw APIError.server(status: 400, code: "invalid_request", message: "Unknown bot, or a rating outside the range of the custom bot.") }
        let human = session(token).user.name
        let white = game.userColor == "white"
        return GameDetail(
            id: "game-\(count)", source: "BOT", white: white ? human : name, black: white ? name : human,
            whiteElo: white ? nil : rating, blackElo: white ? rating : nil, result: game.result, timeClass: "casual",
            opening: nil, userColor: game.userColor, playedAt: .now, ply: GameLine(pgn: game.pgn).moves.count,
            starred: false, reviewed: false, pgn: game.pgn, url: nil, review: nil
        )
    }

    private func session(_ token: String) -> AuthSession {
        AuthSession(
            token: token, expiresAt: Date(timeIntervalSinceNow: 3600),
            user: APIUser(id: "u1", email: "ana@example.com", name: "Ana Silva", role: "STUDENT", emailVerified: true)
        )
    }

    func login(email: String, password: String) async throws -> AuthSession { session("token") }
    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession { session("token") }
    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession { session("token") }
    func resendVerification(token: String) async throws {}
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {}
    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me { try await me(token: token) }
    func refresh(token: String) async throws -> AuthSession { session(token) }

    func me(token: String) async throws -> Me {
        Me(
            user: session(token).user, hasPassword: true,
            access: .init(premium: false, paid: false, viaCoachPlan: false, viaAppStore: false,
                          trial: .init(status: "available", endsAt: nil, daysLeft: nil)),
            freeLimits: .init(repertoireLines: 20, explorerGames: 100)
        )
    }

    func courses(token: String?) async throws -> [CourseCard] { try await guest.courses(token: token) }
    func course(slug: String, token: String?) async throws -> CourseDetail { try await guest.course(slug: slug, token: token) }
    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        try await guest.courseSession(slug: slug, mode: mode, line: line, token: token)
    }

    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws {}
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { 0 }
    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {}
    func due(token: String) async throws -> DueSummary { try await guest.due(token: token) }
    func paths(token: String?) async throws -> [PathCard] { try await guest.paths(token: token) }
    func path(slug: String, token: String?) async throws -> PathDetail { try await guest.path(slug: slug, token: token) }
    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        try await guest.pathSession(slug: slug, stage: stage, token: token)
    }

    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { 0 }
}

/// A place on disk of its own for every test.
private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "play-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func appModel(_ api: any ChessDeskAPI) -> AppModel {
    let tokens = MemoryTokenStore()
    return AppModel(
        backend: .sampleData, api: api,
        guestStore: GuestProgressStore(url: temporaryFolder().appending(path: "guest.json")),
        makeTokenStore: { _ in tokens }
    )
}

/// Maria, the second bot of the roster, with the catalogue's numbers.
private func setup(
    _ side: Side = .white, firstMove: String? = nil, start: BotStart = .standard
) -> BotGameSetup {
    BotGameSetup(
        botID: "philippines", botName: "Maria", rating: 446, avatar: "https://chessdesk.app/bots/philippines.webp",
        country: "Philippines", humanSide: side, firstMove: firstMove, temperature: 1.33, stockfishElo: 1320, start: start
    )
}

/// The engines as the captured catalogue sets them.
private func catalogueEngines() throws -> PlayEngines {
    try FixtureAPI.playCatalogue().engines
}

private func move(_ uci: String) -> Move { Move(uci: uci).unsafelyUnwrapped }

/// Plays a line where the player and the bot alternate, the player first or
/// second according to the side to move.
private func played(_ uci: String, in setup: BotGameSetup) throws -> BotGame {
    var game = try #require(BotGame(setup: setup))
    for text in uci.split(separator: " ").map(String.init) {
        if game.humanToMove {
            let step1 = game.playHuman(move(text))
            try #require(step1 != nil, "the player's \(text) was refused")
        } else {
            let step2 = game.playBot(answer: text)
            try #require(step2?.move.uci == text, "the bot's \(text) was refused")
        }
    }
    return game
}

/// Waits for something the model does on its own (the bot's reply, a save).
private func eventually(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let limit = clock.now + timeout
    while clock.now < limit {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Answers a list of moves in order, then repeats the last.
private func scripted(_ moves: String, kind: BotEngineKind = .maia) -> StubBotEngine {
    let script = Script(moves.split(separator: " ").map(String.init))
    return StubBotEngine(kind: kind) { _ in await script.next() }
}

private actor Script {
    private var moves: [String]
    init(_ moves: [String]) { self.moves = moves }
    func next() -> String { moves.count > 1 ? moves.removeFirst() : moves.first ?? "0000" }
}

// MARK: Art

@Suite struct PlayArtTests {
    @Test func artIsReadFromTheSite() {
        #expect(PlayAssets.url("/bots/peru.webp")?.absoluteString == "https://chessdesk.app/bots/peru.webp")
        #expect(PlayAssets.url("https://cdn.example/b.webp")?.absoluteString == "https://cdn.example/b.webp")
        #expect(PlayAssets.url("peru.webp") == nil)
    }

    @Test func everyCountryOfTheRosterHasAFlag() throws {
        for bot in try FixtureAPI.playCatalogue().bots {
            #expect(CountryFlag.emoji(for: bot.country) != nil, "\(bot.country)")
        }
        #expect(CountryFlag.emoji(for: "Peru") == "🇵🇪")
        #expect(CountryFlag.emoji(for: "USA") == "🇺🇸")
        #expect(CountryFlag.emoji(for: "China") == "🇨🇳")
        #expect(CountryFlag.emoji(for: "England")?.unicodeScalars.first?.value == 0x1F3F4)
        #expect(CountryFlag.emoji(for: "South Korea") == "🇰🇷")
        #expect(CountryFlag.emoji(for: "Atlantis") == nil)
        #expect(CountryFlag.emoji(for: nil) == nil)
    }
}

// MARK: The game

/// A whole game without an engine or a screen: the flow of the site's
/// `use-bot-game.ts`, with the cases of `use-bot-game.test.ts`.
@Suite struct BotGameTests {
    @Test func aWinByCheckmate() throws {
        var game = try played("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6", in: setup(.white))
        #expect(!game.isOver)
        #expect(game.humanToMove)
        #expect(game.result == nil)
        let step3 = game.playHuman(move("h5f7"))
        try #require(step3 != nil)
        #expect(game.termination == .checkmate)
        #expect(game.result == "1-0")
        #expect(game.outcome?.tone == .win)
        #expect(!game.humanToMove && !game.botToMove)
        // A move after the end is ignored.
        let step4 = game.playHuman(move("e1e2"))
        #expect(step4 == nil)
        let step5 = game.playBot(answer: "e8f7")
        #expect(step5 == nil)
        #expect(game.moves.count == 7)
    }

    @Test func aLossByCheckmate() throws {
        let game = try played("f2f3 e7e5 g2g4 d8h4", in: setup(.white))
        #expect(game.termination == .checkmate)
        #expect(game.result == "0-1")
        #expect(game.outcome?.tone == .loss)
        #expect(game.outcome?.title(botName: "Maria") == "Checkmate — you lost")
    }

    @Test func aDrawByRepetitionEndsTheGameAtOnce() throws {
        var game = try played("g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1", in: setup(.white))
        #expect(!game.isOver)
        // The start position, for the third time.
        let step6 = game.playBot(answer: "f6g8")
        try #require(step6 != nil)
        #expect(game.termination == .repetition)
        #expect(game.result == "1/2-1/2")
        #expect(game.outcome?.tone == .draw)
        let step7 = game.playHuman(move("e2e4"))
        #expect(step7 == nil)
    }

    @Test func fiftyMovesStalemateAndBareKingsAreDraws() throws {
        let fifty = try played("a1a2", in: setup(.white, start: BotStart(fen: "8/8/8/8/8/5k2/8/R4K2 w - - 99 80")))
        #expect(fifty.termination == .fiftyMove)
        #expect(fifty.result == "1/2-1/2")

        let stalemate = try played("g5g6", in: setup(.white, start: BotStart(fen: "7k/5K2/8/6Q1/8/8/8/8 w - - 0 1")))
        #expect(stalemate.termination == .stalemate)
        #expect(stalemate.outcome?.title(botName: "Maria") == "Stalemate — a draw")

        let bare = try played("g1g2", in: setup(.white, start: BotStart(fen: "8/8/8/8/8/4k3/6p1/6K1 w - - 0 1")))
        #expect(bare.termination == .insufficientMaterial)
        #expect(bare.result == "1/2-1/2")
    }

    @Test func resigningIsALossForThePlayersSide() throws {
        var white = try played("e2e4 e7e5", in: setup(.white))
        white.resign()
        #expect(white.termination == .resignation)
        #expect(white.result == "0-1")
        #expect(white.outcome?.headline == "You resigned")
        let step8 = white.playHuman(move("g1f3"))
        #expect(step8 == nil)

        var black = try #require(BotGame(setup: setup(.black)))
        black.resign()
        #expect(black.result == "1-0")
        // Resigning a finished game changes nothing.
        var won = try played("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7", in: setup(.white))
        won.resign()
        #expect(won.termination == .checkmate)
        #expect(won.result == "1-0")
    }

    @Test func eachSideMovesOnItsTurnOnly() throws {
        var game = try #require(BotGame(setup: setup(.white)))
        #expect(game.humanToMove)
        let step9 = game.playBot(answer: "e2e4")
        #expect(step9 == nil)
        // An illegal move, and a move of the other side's piece.
        let step10 = game.playHuman(move("e2e5"))
        #expect(step10 == nil)
        let step11 = game.playHuman(move("e7e5"))
        #expect(step11 == nil)
        #expect(game.moves.isEmpty)
        let step12 = game.playHuman(move("e2e4"))
        try #require(step12 != nil)
        #expect(game.botToMove)
        let step13 = game.playHuman(move("d2d4"))
        #expect(step13 == nil)
        #expect(game.moves.count == 1)
    }

    @Test func theBotMovesFirstWhenThePlayerIsBlack() throws {
        var game = try #require(BotGame(setup: setup(.black)))
        #expect(game.botToMove)
        let step14 = game.playHuman(move("e7e5"))
        #expect(step14 == nil)
        let step15 = game.playBot(answer: "e2e4")
        #expect(step15?.san == "e4")
        #expect(game.humanToMove)
    }

    @Test func anAnswerThatIsNotAMoveNeverFreezesTheGame() throws {
        // "a1a8" is no reply to 1.e4; no answer at all is a hung engine.
        for answer in ["a1a8", "garbage", nil] as [String?] {
            var game = try played("e2e4", in: setup(.white))
            let before = game.position
            let step16 = game.playBot(answer: answer, random: { $0.lowerBound })
            let reply = try #require(step16)
            #expect(before.isLegal(reply.move))
            #expect(game.moves.count == 2)
            #expect(game.humanToMove)
        }
    }

    @Test func theSignatureOpeningIsPlayedOnlyOnTheFirstMoveAsWhite() throws {
        #expect(BotGame(setup: setup(.black, firstMove: "c2c4"))?.signatureMove?.uci == "c2c4")
        // The player has White, so the bot does not open.
        #expect(BotGame(setup: setup(.white, firstMove: "c2c4"))?.signatureMove == nil)
        // Not a legal first move: never played.
        #expect(BotGame(setup: setup(.black, firstMove: "e2e5"))?.signatureMove == nil)
        #expect(BotGame(setup: setup(.black, firstMove: nil))?.signatureMove == nil)
        // Not from a position of the player's own.
        let custom = BotStart(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 40")
        #expect(BotGame(setup: setup(.black, firstMove: "e2e4", start: custom))?.signatureMove == nil)
        // And not later in the game.
        let later = try played("e2e4 e7e5", in: setup(.black, firstMove: "e2e4"))
        #expect(later.signatureMove == nil)
    }

    /// The engine is asked at the strength the game was set up with.
    @Test func theSetupCarriesTheStrengthTheEngineIsAskedAt() {
        #expect(setup().strength == BotStrength(rating: 446, temperature: 1.33, stockfishElo: 1320))
    }

    @Test func continuesAPastedPGNAndExportsTheWholeGame() throws {
        let start = try BotStart.parse("1. e4 e5 2. Nf3 Nc6 3. Bb5").get()
        var game = try #require(BotGame(setup: setup(.white, start: start)))
        // Black to move after 3.Bb5: the bot replies straight away.
        #expect(game.botToMove)
        let step17 = game.playBot(answer: "g8f6")
        try #require(step17 != nil)
        #expect(game.moves.count == 6)
        #expect(game.moves[5].san == "Nf6")
        #expect(game.moves[5].ply == 6)
        #expect(game.humanToMove)
        #expect(game.pgn(humanName: "Me").contains("1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6"))
    }

    @Test func startsFromAFENAndRecordsItInThePGN() throws {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 40"
        var game = try #require(BotGame(setup: setup(.white, start: try BotStart.parse(fen).get())))
        #expect(game.position.fen == fen)
        let step18 = game.playHuman(move("e2e4"))
        try #require(step18 != nil)
        #expect(game.moves[0].san == "e4")
        #expect(game.moves[0].ply == 79)
        let pgn = game.pgn(humanName: "Me")
        #expect(pgn.contains("[FEN \"\(fen)\"]"))
        #expect(pgn.contains("40. e4"))
    }

    @Test func thePGNNamesThePlayers() throws {
        let pgn = try played("e2e4 e7e5", in: setup(.white)).pgn(humanName: "Me")
        #expect(pgn.contains("1. e4 e5"))
        #expect(pgn.contains("[White \"Me\"]"))
        #expect(pgn.contains("[Black \"Maria\"]"))
        #expect(pgn.contains("[Result \"*\"]"))
        // The app's own reader takes it back, move for move.
        let finished = try played("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7", in: setup(.white))
        let line = GameLine(pgn: finished.pgn(humanName: "Me"))
        #expect(line.moves.map(\.san) == finished.moves.map(\.san))
        #expect(line.headers["Result"] == "1-0")
    }

    /// The body of `POST /api/v1/play/games`: the bot by its id, never its
    /// name or rating (the server reads those from its catalogue).
    @Test func aFinishedGameIsSentAsTheContractAsks() throws {
        let game = try played("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7", in: setup(.white))
        let request = game.saveRequest(humanName: "Ana Silva", engine: .maia)
        #expect(request.bot == "philippines")
        #expect(request.rating == nil)
        #expect(request.result == "1-0")
        #expect(request.userColor == "white")
        #expect(request.engine == "maia-3")
        #expect(request.pgn.contains("[Event \"Bot game\"]"))
        #expect(request.pgn.contains("[White \"Ana Silva\"]"))
        let json = try #require(JSONSerialization.jsonObject(with: APICoding.encoder.encode(request)) as? [String: Any])
        #expect(Set(json.keys) == ["bot", "userColor", "result", "engine", "pgn"])

        let asBlack = try played("f2f3 e7e5 g2g4 d8h4", in: setup(.black)).saveRequest(humanName: "You", engine: .stockfish)
        #expect(asBlack.userColor == "black")
        #expect(asBlack.engine == "stockfish")
        #expect(asBlack.result == "0-1")

        // The custom bot's rating is the player's choice, so it is sent.
        let catalogue = try FixtureAPI.playCatalogue()
        let built = OpponentPick.custom(catalogue.custom).setup(rating: 1230, humanSide: .white, start: .standard, engines: catalogue.engines)
        let custom = try played("f2f3 e7e5 g2g4 d8h4", in: built).saveRequest(humanName: "You", engine: .maia)
        #expect(custom.bot == "custom")
        #expect(custom.rating == 1230)
        let customJSON = try #require(JSONSerialization.jsonObject(with: APICoding.encoder.encode(custom)) as? [String: Any])
        #expect(customJSON["rating"] as? Int == 1230)
    }

    @Test func aPawnReachingTheLastRankWithoutAPieceNamedBecomesAQueen() throws {
        var game = try #require(BotGame(setup: setup(.white, start: BotStart(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1"))))
        let step19 = game.playHuman(move("a7a8"))
        #expect(step19?.san == "a8=Q")
        var knight = try #require(BotGame(setup: setup(.white, start: BotStart(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1"))))
        let step20 = knight.playHuman(move("a7a8n"))
        #expect(step20?.san == "a8=N")
    }
}

// MARK: Kept on the device

@Suite struct BotGameStoreTests {
    @Test func aGameComesBackAsItWasLeft() throws {
        let game = try played("e2e4 e7e5 g1f3", in: setup(.white, firstMove: "e2e4"))
        let snapshot = BotGameSnapshot(game, engine: .maia)
        // Through JSON, as on disk.
        let read = try JSONDecoder().decode(BotGameSnapshot.self, from: JSONEncoder().encode(snapshot))
        let restored = try #require(read.restored())
        #expect(restored == game)
        #expect(restored.moves.map(\.san) == ["e4", "e5", "Nf3"])
        #expect(restored.botToMove)
        #expect(read.engine == .maia)
        #expect(read.setup == game.setup)
    }

    @Test func aGameFromAPastedPositionComesBackWhole() throws {
        let start = try BotStart.parse("1. e4 e5 2. Nf3").get()
        let game = try played("b8c6 f1b5", in: setup(.white, start: start))
        let restored = try #require(BotGameSnapshot(game, engine: .stockfish).restored())
        #expect(restored.moves.map(\.san) == ["e4", "e5", "Nf3", "Nc6", "Bb5"])
        #expect(restored.setup.start.moves.count == 3)
    }

    @Test func aFileThatIsNotALegalGameIsDropped() throws {
        var snapshot = BotGameSnapshot(try played("e2e4 e7e5", in: setup(.white)), engine: .maia)
        snapshot.moves = ["e2e4", "e7e5", "e4e5"]
        #expect(snapshot.restored() == nil)
        snapshot.moves = ["e2e4", "zz"]
        #expect(snapshot.restored() == nil)
        // Preset moves that do not match the start.
        var preset = BotGameSnapshot(try played("b8c6", in: setup(.white, start: try BotStart.parse("1. e4 e5 2. Nf3").get())), engine: .maia)
        preset.moves = ["d2d4", "e7e5", "g1f3", "b8c6"]
        #expect(preset.restored() == nil)
    }

    @Test func theStoreHoldsTheGameInProgressAndForgetsAFinishedOne() throws {
        let store = BotGameStore(folder: temporaryFolder())
        #expect(store.current() == nil)
        let game = try played("e2e4 e7e5", in: setup(.white))
        store.setCurrent(BotGameSnapshot(game, engine: .maia))
        #expect(store.current()?.restored() == game)
        // A relaunch reads the same file.
        #expect(BotGameStore(folder: store.folder).current()?.moves == ["e2e4", "e7e5"])

        var resigned = game
        resigned.resign()
        store.setCurrent(BotGameSnapshot(resigned, engine: .maia))
        #expect(store.current() == nil)
        store.setCurrent(BotGameSnapshot(game, engine: .maia))
        store.setCurrent(nil)
        #expect(store.current() == nil)
    }

    /// The site's `pending-game.test.ts`: a week, no more, and not from the future.
    @Test func aFinishedGameWaitsAWeekForAnAccount() throws {
        let store = BotGameStore(folder: temporaryFolder())
        let request = try played("f2f3 e7e5 g2g4 d8h4", in: setup(.white)).saveRequest(humanName: "You", engine: .maia)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.setPending(PendingBotGame(request: request, savedAt: now))
        #expect(store.pending(now: now.addingTimeInterval(6 * 24 * 3600))?.request == request)
        #expect(store.pending(now: now.addingTimeInterval(-60)) == nil)
        store.setPending(PendingBotGame(request: request, savedAt: now))
        #expect(store.pending(now: now.addingTimeInterval(8 * 24 * 3600)) == nil)
        // An expired game is removed, not kept for later.
        #expect(store.pending(now: now) == nil)
    }
}

// MARK: Start positions

/// The site's `start-position.test.ts`.
@Suite struct BotStartTests {
    @Test func acceptsAFullFEN() throws {
        let start = try BotStart.parse("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3").get()
        #expect(start.moves.isEmpty)
        #expect(start.turn == .white)
        #expect(!start.isStandard)
    }

    @Test func completesAFENMissingItsCounters() throws {
        #expect(try BotStart.parse("4k3/8/8/8/8/8/4P3/4K3 b").get().fen == "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1")
    }

    @Test func replaysAPGNMainLineAndDropsVariationsAndComments() throws {
        let start = try BotStart.parse("[Event \"x\"]\n\n1. e4 {best} e5 (1... c5 2. Nf3) 2. Nf3 *").get()
        #expect(start.fen == Position.startFEN)
        #expect(start.moves == ["e2e4", "e7e5", "g1f3"])
        #expect(start.turn == .black)
        #expect(start.game?.moves.map(\.san) == ["e4", "e5", "Nf3"])
    }

    @Test func refusesEmptyInputAnIllegalFENAndAFinishedGame() {
        #expect(BotStart.parse("  ") == .failure(.empty))
        #expect(BotStart.parse("8/8/8/8/8/8/8/8 w - - 0 1") == .failure(.illegalFEN))
        #expect(BotStart.ParseError.illegalFEN.message.contains("not a legal"))
        #expect(BotStart.parse("4k2P/8/8/8/8/8/8/4K3 w - - 0 1") == .failure(.illegalFEN))
        #expect(BotStart.parse("1. f3 e5 2. g4 Qh4# 0-1") == .failure(.alreadyFinished))
        #expect(BotStart.ParseError.alreadyFinished.message.contains("already finished"))
        #expect(BotStart.parse("7k/5K2/6Q1/8/8/8/8/8 b - - 0 1") == .failure(.alreadyFinished))
        #expect(BotStart.parse(String(repeating: "e4 ", count: 40_000)) == .failure(.tooLong))
    }

    @Test func refusesTextWithNoMoves() {
        #expect(BotStart.parse("hello there") == .failure(.noMoves))
    }

    @Test func tellsAFENFromAPGN() {
        #expect(BotStart.looksLikeFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
        #expect(BotStart.looksLikeFEN("4k3/8/8/8/8/8/4P3/4K3"))
        #expect(!BotStart.looksLikeFEN("1. e4 e5"))
        #expect(!BotStart.looksLikeFEN("[Event \"x\"]"))
        #expect(!BotStart.looksLikeFEN("4k3/8/8/8/8/8/4P3"))
        #expect(!BotStart.looksLikeFEN("4k3/9/8/8/8/8/4P3/4K3"))
    }
}

// MARK: Material

/// The site's `material.test.ts`.
@Suite struct MaterialDiffTests {
    private func diff(_ fen: String) throws -> MaterialDiff {
        MaterialDiff(position: try #require(Position(fen: fen)))
    }

    private func after(_ moves: String, from fen: String = Position.startFEN) throws -> MaterialDiff {
        let start = try #require(Position(fen: fen))
        let game = try #require(Game(start: start, uciMoves: moves.split(separator: " ").map(String.init)))
        return MaterialDiff(position: game.position)
    }

    private func groups(_ pairs: (PieceKind, Int)...) -> [MaterialDiff.Group] {
        pairs.map { MaterialDiff.Group(kind: $0.0, count: $0.1) }
    }

    @Test func showsNothingAtTheStart() throws {
        let start = try diff(Position.startFEN)
        #expect(start.white.captured.isEmpty && start.black.captured.isEmpty)
        #expect(start.white.advantage == 0 && start.black.advantage == 0)
    }

    @Test func creditsACaptureToTheCapturingSideWithItsLead() throws {
        let diff = try after("e2e4 d7d5 e4d5")
        #expect(diff.white.captured == groups((.pawn, 1)))
        #expect(diff.white.advantage == 1)
        #expect(diff.black.captured.isEmpty)
        #expect(diff.black.advantage == 0)
        #expect(diff[.white] == diff.white)
    }

    @Test func groupsByTypePawnToQueenAndNetsTheLead() throws {
        let diff = try diff("r1b1kb1r/pp1pp1pp/8/8/8/8/PPPPPPPP/1NBQKBNR w Kkq - 0 1")
        #expect(diff.white.captured == groups((.pawn, 2), (.knight, 2), (.queen, 1)))
        #expect(diff.black.captured == groups((.rook, 1)))
        #expect(diff.white.advantage == 2 + 6 + 9 - 5)
        #expect(diff.black.advantage == 0)
    }

    @Test func showsBothCapturesButNoLeadAfterAnEqualTrade() throws {
        let diff = try after("e2e4 d7d5 e4d5 d8d5")
        #expect(diff.white.captured == groups((.pawn, 1)))
        #expect(diff.black.captured == groups((.pawn, 1)))
        #expect(diff.white.advantage == 0 && diff.black.advantage == 0)
    }

    @Test func aPromotedPawnIsNotACapture() throws {
        let diff = try diff("Q1bqkbnr/1ppppppp/8/8/8/8/1PPPPPPP/RNBQKBNR b KQk - 0 1")
        #expect(diff.white.captured == groups((.pawn, 1), (.knight, 1), (.rook, 1)))
        #expect(diff.black.captured.isEmpty)
        #expect(diff.white.advantage == 1 + 3 + 5 + 8)
        #expect(diff.black.advantage == 0)
    }

    @Test func staysRightWhenAPromotionIsPlayed() throws {
        let before = "4k3/P7/8/8/8/8/8/Q3K3 w - - 0 1"
        #expect(try diff(before).white.advantage == 10)
        #expect(try after("a7a8q", from: before).white.advantage == 18)
        #expect(try after("a7a8q", from: before).black.captured == (try diff(before).black.captured))
    }
}

// MARK: Results in words

/// The site's `outcome.test.ts`.
@Suite struct BotGameOutcomeTests {
    private func outcome(_ result: String?, _ termination: BotGameTermination, _ side: Side = .white) -> BotGameOutcome {
        BotGameOutcome(result: result, termination: termination, humanSide: side)
    }

    @Test func scoresADecisiveResultFromThePlayersSide() {
        for side in Side.allCases {
            let win = side == .white ? "1-0" : "0-1"
            let loss = side == .white ? "0-1" : "1-0"
            for termination in [BotGameTermination.checkmate, .resignation, .timeout] {
                #expect(outcome(win, termination, side).tone == .win)
                #expect(outcome(loss, termination, side).tone == .loss)
            }
        }
    }

    @Test func aDrawnTerminationAlwaysScoresHalfAPoint() {
        for termination in [BotGameTermination.stalemate, .repetition, .fiftyMove, .insufficientMaterial, .agreement] {
            let drawn = outcome("1-0", termination)
            #expect(drawn.tone == .draw)
            #expect(drawn.result == "1/2-1/2")
            #expect(drawn.termination == termination)
        }
        // A decisive ending without a result reads as a draw agreed.
        #expect(outcome(nil, .checkmate).termination == .agreement)
    }

    /// Side, result, termination, title, headline, method, the bot's line.
    @Test(arguments: [
        (Side.white, "1-0", BotGameTermination.checkmate, "Checkmate — you won", "You won", "by checkmate in 9 moves", "Checkmated"),
        (.black, "0-1", .checkmate, "Checkmate — you won", "You won", "by checkmate in 9 moves", "Checkmated"),
        (.white, "0-1", .checkmate, "Checkmate — you lost", "You lost", "by checkmate in 9 moves", "Won by checkmate"),
        (.black, "1-0", .checkmate, "Checkmate — you lost", "You lost", "by checkmate in 9 moves", "Won by checkmate"),
        (.white, "1-0", .resignation, "Maria resigned — you won", "You won", "by resignation after 9 moves", "Resigned"),
        (.black, "1-0", .resignation, "You resigned", "You resigned", "by resignation after 9 moves", "Won by resignation"),
        (.white, "1-0", .timeout, "Maria ran out of time — you won", "You won", "on time", "Lost on time"),
        (.black, "1-0", .timeout, "Out of time — you lost", "You lost", "on time", "Won on time"),
        (.white, "1/2-1/2", .stalemate, "Stalemate — a draw", "Draw", "by stalemate", "Drew by stalemate"),
        (.black, "1/2-1/2", .repetition, "Draw by repetition", "Draw", "by threefold repetition", "Drew by threefold repetition"),
        (.white, "1/2-1/2", .fiftyMove, "Draw by the 50-move rule", "Draw", "by the 50-move rule", "Drew by the 50-move rule"),
        (.black, "1/2-1/2", .insufficientMaterial, "Draw — insufficient material", "Draw", "by insufficient material", "Drew by insufficient material"),
        (.white, "1/2-1/2", .agreement, "Draw agreed", "Draw", "by agreement", "Drew by agreement"),
    ])
    func copyForEveryOutcome(
        side: Side, result: String, termination: BotGameTermination,
        title: String, headline: String, method: String, bot: String
    ) {
        let outcome = outcome(result, termination, side)
        #expect(outcome.title(botName: "Maria") == title)
        #expect(outcome.headline == headline)
        #expect(outcome.terminationPhrase(lastMoveNumber: 9) == method)
        #expect(outcome.botStatusLine == bot)
    }

    @Test func oneMoveIsSingularAndAnUnknownCountIsLeftOut() {
        #expect(outcome("1-0", .checkmate).terminationPhrase(lastMoveNumber: 1) == "by checkmate in 1 move")
        #expect(outcome("1-0", .checkmate).terminationPhrase() == "by checkmate")
        #expect(outcome("0-1", .resignation).terminationPhrase() == "by resignation")
    }

    @Test func theScoreSheetEndsLikeAPrintedGame() {
        #expect(outcome("0-1", .checkmate).scoreSheetEnding == "Black wins by checkmate")
        #expect(outcome("0-1", .resignation).scoreSheetEnding == "White resigns")
        #expect(outcome("1-0", .timeout, .black).scoreSheetEnding == "White wins on time")
        #expect(outcome("1/2-1/2", .stalemate, .black).scoreSheetEnding == "Draw by stalemate")
        #expect(BotGameOutcome.printedScore("1-0") == "1–0")
        #expect(BotGameOutcome.printedScore("1/2-1/2") == "½–½")
        #expect(BotGameOutcome.moveNumber(ofPly: 17) == 9)
        #expect(BotGameOutcome.moveNumber(ofPly: 18) == 9)
        #expect(outcome("1-0", .checkmate).terminationName == "Checkmate")
        #expect(outcome("1/2-1/2", .fiftyMove).terminationName == "50-move rule")
    }

    @Test func theRulesOfTheBoardMapToTheSitesTerminations() {
        #expect(BotGameTermination(.checkmate(winner: .white)) == .checkmate)
        #expect(BotGameTermination(.stalemate) == .stalemate)
        #expect(BotGameTermination(.insufficientMaterial).rawValue == "insufficient-material")
        #expect(BotGameTermination(.threefoldRepetition) == .repetition)
        #expect(BotGameTermination(.fiftyMoveRule).rawValue == "fifty-move")
    }
}

// MARK: The game on screen

/// The model of the game screen, with a stub engine and a stub server.
@Suite struct BotGameModelTests {
    private func model(
        _ setup: BotGameSetup,
        engine: any BotEngine,
        app: AppModel? = nil,
        store: BotGameStore? = nil,
        timeout: Duration = .seconds(5)
    ) throws -> BotGameModel {
        BotGameModel(
            game: try #require(BotGame(setup: setup)), engine: engine, app: app ?? appModel(FixtureAPI(delay: .zero)),
            store: store, moveTimeout: timeout, replyFloor: .zero
        )
    }

    @Test func playsThePlayersMoveThenTheBotsReply() async throws {
        let model = try model(setup(.white), engine: StubBotEngine(move: "e7e5"))
        model.begin()
        #expect(model.game.humanToMove)
        #expect(model.play(move("e2e4")))
        #expect(model.thinking)
        #expect(await eventually { model.game.moves.count == 2 })
        #expect(model.game.moves.map(\.san) == ["e4", "e5"])
        // Back to the player: not stuck on "thinking".
        #expect(!model.thinking)
        #expect(model.game.humanToMove)
        #expect(!model.game.isOver)
    }

    @Test func refusesAnIllegalMoveAndAMoveOutOfTurn() async throws {
        let slow = StubBotEngine { _ in
            try await Task.sleep(for: .milliseconds(200))
            return "e7e5"
        }
        let model = try model(setup(.white), engine: slow)
        model.begin()
        #expect(!model.play(move("e2e5")))
        #expect(model.play(move("e2e4")))
        // The bot is thinking: the player cannot move twice.
        #expect(!model.play(move("d2d4")))
        #expect(model.game.moves.count == 1)
        #expect(await eventually { model.game.moves.count == 2 })
    }

    @Test func letsTheBotMoveFirstWhenThePlayerIsBlack() async throws {
        let model = try model(setup(.black), engine: StubBotEngine(move: "d2d4"))
        model.begin()
        #expect(await eventually { model.game.moves.count == 1 })
        #expect(model.game.moves[0].san == "d4")
        #expect(model.game.humanSide == .black)
    }

    @Test func theBotOpensWithItsSignatureMoveOnce() async throws {
        // The engine would play 1.d4; the character opens 1.c4.
        let model = try model(setup(.black, firstMove: "c2c4"), engine: StubBotEngine(move: "d2d4"))
        model.begin()
        model.begin()
        #expect(await eventually { model.game.humanToMove })
        #expect(model.game.moves.map(\.san) == ["c4"])
    }

    @Test func aGarbageAnswerStillGivesAMove() async throws {
        let model = try model(setup(.white), engine: StubBotEngine(move: "a1a8"))
        model.begin()
        #expect(model.play(move("e2e4")))
        #expect(await eventually { model.game.moves.count == 2 })
        #expect(model.game.humanToMove)
    }

    @Test func anEngineThatNeverAnswersDoesNotHoldTheGame() async throws {
        let hung = StubBotEngine { _ in
            try await Task.sleep(for: .seconds(600))
            return "e2e4"
        }
        let model = try model(setup(.black), engine: hung, timeout: .milliseconds(80))
        model.begin()
        #expect(await eventually { model.game.moves.count == 1 })
        #expect(!model.thinking)
    }

    @Test func resigningWhileTheBotThinksDropsItsLateMove() async throws {
        let late = StubBotEngine { _ in
            try await Task.sleep(for: .milliseconds(150))
            return "e7e5"
        }
        let model = try model(setup(.white), engine: late)
        model.begin()
        #expect(model.play(move("e2e4")))
        #expect(model.thinking)
        model.resign()
        #expect(model.game.termination == .resignation)
        #expect(model.game.result == "0-1")
        #expect(!model.thinking)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.game.moves.count == 1)
    }

    @Test func leavingTheScreenHoldsTheGameAndComingBackResumesIt() async throws {
        let slow = StubBotEngine { _ in
            try await Task.sleep(for: .milliseconds(120))
            return "e7e5"
        }
        let model = try model(setup(.white), engine: slow)
        model.begin()
        #expect(model.play(move("e2e4")))
        model.pause()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.game.moves.count == 1)
        model.begin()
        #expect(await eventually { model.game.moves.count == 2 })
    }

    @Test func theSoundOfEveryMoveIsAsked() async throws {
        let model = try model(setup(.white), engine: scripted("d7d5 d8d5"))
        var captures: [Bool] = []
        model.onMovePlayed = { captures.append($0) }
        model.begin()
        #expect(model.play(move("e2e4")))
        #expect(await eventually { model.game.moves.count == 2 })
        #expect(model.play(move("e4d5")))
        #expect(await eventually { model.game.moves.count == 4 })
        #expect(captures == [false, false, true, true])
    }

    // MARK: A whole game, kept and saved

    @Test func aWinIsSavedToTheAccountAtOnce() async throws {
        let server = PlayServer()
        let app = appModel(server)
        try await app.signIn(email: "ana@example.com", password: "x")
        let store = BotGameStore(folder: temporaryFolder())
        let model = try model(setup(.white), engine: scripted("e7e5 b8c6 g8f6", kind: .maia), app: app, store: store)
        model.begin()
        for text in ["e2e4", "d1h5", "f1c4"] {
            let count = model.game.moves.count
            #expect(model.play(move(text)))
            #expect(await eventually { model.game.moves.count == count + 2 })
            // The game is on the device after every move.
            #expect(store.current()?.moves.count == model.game.moves.count)
        }
        #expect(model.play(move("h5f7")))
        #expect(model.game.termination == .checkmate)
        #expect(model.game.outcome?.tone == .win)
        await model.waitForSave()
        #expect(model.saving == .saved(gameID: "game-1"))
        let saved = try #require(server.saved.first)
        #expect(saved.result == "1-0")
        #expect(saved.engine == "maia-3")
        #expect(saved.bot == "philippines")
        #expect(saved.userColor == "white")
        #expect(saved.pgn.contains("[White \"Ana Silva\"]"))
        #expect(saved.pgn.contains("4. Qxf7# 1-0"))
        // A finished game is no longer "in progress".
        #expect(store.current() == nil)
        // Saving twice is not possible.
        model.save()
        await model.waitForSave()
        #expect(server.saved.count == 1)
    }

    @Test func aLossAndADrawAreSavedWithTheirResult() async throws {
        let server = PlayServer()
        let app = appModel(server)
        try await app.signIn(email: "ana@example.com", password: "x")

        let lost = try model(setup(.white), engine: scripted("e7e5 d8h4", kind: .stockfish), app: app)
        lost.begin()
        #expect(lost.play(move("f2f3")))
        #expect(await eventually { lost.game.moves.count == 2 })
        #expect(lost.play(move("g2g4")))
        #expect(await eventually { lost.game.isOver })
        #expect(lost.game.outcome?.tone == .loss)
        #expect(await eventually { lost.saving == .saved(gameID: "game-1") })
        #expect(server.saved[0].result == "0-1")
        #expect(server.saved[0].engine == "stockfish")

        let drawn = try model(setup(.white), engine: scripted("g8f6 f6g8 g8f6 f6g8", kind: .maia), app: app)
        drawn.begin()
        for text in ["g1f3", "f3g1", "g1f3", "f3g1"] {
            let count = drawn.game.moves.count
            #expect(drawn.play(move(text)))
            #expect(await eventually { drawn.game.moves.count == count + 2 })
        }
        #expect(drawn.game.termination == .repetition)
        #expect(await eventually { drawn.saving == .saved(gameID: "game-2") })
        #expect(server.saved[1].result == "1/2-1/2")
    }

    @Test func aResignationIsSavedAsALoss() async throws {
        let server = PlayServer()
        let app = appModel(server)
        try await app.signIn(email: "ana@example.com", password: "x")
        let model = try model(setup(.black), engine: StubBotEngine(move: "e2e4"), app: app)
        model.begin()
        #expect(await eventually { model.game.moves.count == 1 })
        model.resign()
        await model.waitForSave()
        #expect(model.saving == .saved(gameID: "game-1"))
        #expect(server.saved[0].result == "1-0")
        #expect(server.saved[0].userColor == "black")
        #expect(server.saved[0].bot == "philippines")
    }

    @Test func aGuestsGameWaitsForAnAccountThenIsSaved() async throws {
        let server = PlayServer()
        let app = appModel(server)
        let store = BotGameStore(folder: temporaryFolder())
        let model = try model(setup(.white), engine: StubBotEngine(move: "e7e5"), app: app, store: store)
        model.begin()
        #expect(model.play(move("e2e4")))
        #expect(await eventually { model.game.moves.count == 2 })
        model.resign()
        #expect(model.saving == .waitingForAccount)
        #expect(server.saved.isEmpty)
        #expect(store.pending()?.request.pgn.contains("[White \"You\"]") == true)

        // The player creates an account from the result panel.
        try await app.signIn(email: "ana@example.com", password: "x")
        model.accountChanged()
        await model.waitForSave()
        #expect(model.saving == .saved(gameID: "game-1"))
        #expect(server.saved[0].pgn.contains("[White \"Ana Silva\"]"))
        #expect(store.pending() == nil)
    }

    @Test func aGuestsGameIsClaimedFromTheHubAfterSigningIn() async throws {
        let server = PlayServer()
        let app = appModel(server)
        let store = BotGameStore(folder: temporaryFolder())
        let request = try played("f2f3 e7e5 g2g4 d8h4", in: setup(.white)).saveRequest(humanName: "You", engine: .maia)
        store.setPending(PendingBotGame(request: request))
        let hub = PlayModel(app: app, store: store, cache: nil)
        await hub.claimPendingGame()
        // Still a guest: nothing moves.
        #expect(hub.claimedGameID == nil)
        #expect(store.pending() != nil)
        try await app.signIn(email: "ana@example.com", password: "x")
        await hub.claimPendingGame()
        #expect(hub.claimedGameID == "game-1")
        #expect(server.saved == [request])
        #expect(store.pending() == nil)
        hub.claimedGameShown()
        #expect(hub.claimedGameID == nil)
    }

    @Test func aFailedSaveCanBeTriedAgain() async throws {
        let server = PlayServer(failingSaves: 1)
        let app = appModel(server)
        try await app.signIn(email: "ana@example.com", password: "x")
        let model = try model(setup(.white), engine: StubBotEngine(move: "e7e5"), app: app)
        model.begin()
        model.resign()
        await model.waitForSave()
        #expect(model.saving == .failed(APIError.offline.message))
        model.save()
        await model.waitForSave()
        #expect(model.saving == .saved(gameID: "game-1"))
    }

    /// A signed-in player who finishes without a connection keeps the game:
    /// it waits on the device and is saved when the bots are next opened.
    @Test func aGameFinishedWithoutAConnectionIsSavedLater() async throws {
        let server = PlayServer(failingSaves: 1)
        let app = appModel(server)
        try await app.signIn(email: "ana@example.com", password: "x")
        let store = BotGameStore(folder: temporaryFolder())
        let model = try model(setup(.white), engine: StubBotEngine(move: "e7e5"), app: app, store: store)
        model.begin()
        model.resign()
        await model.waitForSave()
        #expect(model.saving == .failed(APIError.offline.message))
        #expect(store.pending() != nil)
        let hub = PlayModel(app: app, store: store, cache: nil)
        await hub.claimPendingGame()
        #expect(hub.claimedGameID == "game-1")
        #expect(server.saved.count == 1)
        #expect(store.pending() == nil)
    }

    @Test func nothingIsPromisedWhereGamesCannotBeSaved() async throws {
        // Sample data keeps no bot games.
        let store = BotGameStore(folder: temporaryFolder())
        let model = try model(setup(.white), engine: StubBotEngine(move: "e7e5"), store: store)
        model.begin()
        model.resign()
        #expect(model.saving == .unavailable)
        #expect(store.pending() == nil)
    }

    @Test func aRematchStartsAgainOnTheOtherSideIfAsked() async throws {
        let model = try model(setup(.white, firstMove: "c2c4"), engine: StubBotEngine(move: "e7e5"))
        model.begin()
        model.rematch(swappingSides: true)
        // Not while the game is played.
        #expect(model.game.humanSide == .white)
        model.resign()
        model.rematch(swappingSides: true)
        #expect(model.game.humanSide == .black)
        #expect(model.saving == .unavailable || model.saving == .idle)
        // The bot has White now and opens with its move.
        #expect(await eventually { model.game.moves.count == 1 })
        #expect(model.game.moves[0].san == "c4")
        #expect(!model.game.isOver)
        model.resign()
        model.rematch(swappingSides: false)
        #expect(model.game.humanSide == .black)
        #expect(model.game.moves.isEmpty || model.game.moves.count == 1)
    }
}

// MARK: The hub

@Suite struct PlayModelTests {
    private func engines(_ engine: StubBotEngine) -> @Sendable (PlayEngines) -> BotEngineSelection {
        { _ in BotEngineSelection(makeMaia: { engine }, makeStockfish: { engine }, loadBudget: .seconds(5), warmupBudget: .seconds(5)) }
    }

    @Test func loadsTheCatalogue() async {
        let hub = PlayModel(app: appModel(PlayServer()), store: BotGameStore(folder: temporaryFolder()), cache: nil)
        #expect(hub.phase == .loading)
        await hub.load()
        #expect(hub.catalogue?.bots.count == 41)
        #expect(!hub.isFromCache)

        let failing = PlayModel(app: appModel(PlayServer(catalogueFails: true)), store: BotGameStore(folder: temporaryFolder()), cache: nil)
        await failing.load()
        #expect(failing.phase == .failed(APIError.offline.message))
        #expect(failing.catalogue == nil)
    }

    /// The server says whether this session may save; the app asks with its token.
    @Test func theCatalogueIsAskedWithTheSessionAndSaysWhetherGamesAreSaved() async throws {
        let server = PlayServer()
        let app = appModel(server)
        let hub = PlayModel(app: app, store: BotGameStore(folder: temporaryFolder()), cache: nil)
        await hub.load()
        #expect(hub.catalogue?.canSaveGames == false)
        try await app.signIn(email: "ana@example.com", password: "x")
        await hub.load()
        #expect(hub.catalogue?.canSaveGames == true)
        #expect(server.catalogueTokens == [nil, "token"])
    }

    /// The last catalogue the server answered is kept: without a connection
    /// the bots are still there, and a game still starts.
    @Test func theLastCatalogueIsKeptForPlayingWithoutAConnection() async throws {
        let cache = PlayCatalogueCache(folder: temporaryFolder())
        let server = PlayServer()
        let app = appModel(server)
        #expect(cache.catalogue(for: app.backend) == nil)

        // Never loaded and no connection: there is nothing to show.
        server.catalogueFails = true
        let never = PlayModel(app: app, store: BotGameStore(folder: temporaryFolder()), cache: cache)
        await never.load()
        #expect(never.phase == .failed(APIError.offline.message))

        // One visit with a connection keeps the answer on the device.
        server.catalogueFails = false
        let online = PlayModel(app: app, store: BotGameStore(folder: temporaryFolder()), cache: cache)
        await online.load()
        let served = try #require(online.catalogue)
        #expect(!online.isFromCache)
        #expect(cache.catalogue(for: app.backend) == served)
        // Another backend has its own file.
        #expect(cache.catalogue(for: .server(try #require(URL(string: "https://other.example")))) == nil)

        // A new launch without a connection: the kept catalogue, and a game.
        server.catalogueFails = true
        let offline = PlayModel(
            app: app, store: BotGameStore(folder: temporaryFolder()), cache: cache,
            engines: engines(StubBotEngine(kind: .maia, move: "e7e5"))
        )
        await offline.load()
        #expect(offline.catalogue == served)
        #expect(offline.isFromCache)
        let bot = try #require(served.bots.first)
        let game = try #require(await offline.start(OpponentPick.bot(bot).setup(rating: 0, humanSide: .white, start: .standard, engines: served.engines)))
        game.begin()
        #expect(game.play(move("e2e4")))
        #expect(await eventually { game.game.moves.count == 2 })

        // The connection is back: the server's answer replaces the kept one.
        server.catalogueFails = false
        await offline.load()
        #expect(!offline.isFromCache)

        // A file that no longer decodes is ignored, not trusted.
        try Data("{}".utf8).write(to: try #require(try FileManager.default.contentsOfDirectory(at: cache.folder, includingPropertiesForKeys: nil).first))
        #expect(cache.catalogue(for: app.backend) == nil)
    }

    /// Without a catalogue there are no engine settings: no game starts on
    /// numbers the server did not give.
    @Test func noGameStartsWithoutACatalogue() async throws {
        let hub = PlayModel(
            app: appModel(PlayServer(catalogueFails: true)), store: BotGameStore(folder: temporaryFolder()), cache: nil,
            engines: engines(StubBotEngine(move: "e7e5"))
        )
        await hub.load()
        #expect(await hub.start(setup(.white)) == nil)
    }

    /// Every number of a game comes from the catalogue.
    @Test func aPickBecomesTheSetupOfAGame() throws {
        let catalogue = try FixtureAPI.playCatalogue()
        let engines = catalogue.engines
        let bot = try #require(catalogue.bots.first { $0.id == "china" })
        let character = OpponentPick.bot(bot).setup(rating: 999, humanSide: .black, start: .standard, engines: engines)
        #expect(character.botID == "china")
        #expect(character.botName == "Wei")
        // A character keeps its own rating, opening, temperature and Stockfish Elo.
        #expect(character.rating == bot.rating)
        #expect(character.firstMove == bot.firstMove)
        #expect(character.temperature == bot.temperature)
        #expect(character.stockfishElo == bot.stockfishElo)
        #expect(character.avatar == bot.portraitUrl)
        #expect(!character.isCustom)
        #expect(character.humanSide == .black)
        // The weakest bot is under what Stockfish accepts: the catalogue says where it plays.
        let weakest = try #require(catalogue.bots.first)
        let weak = OpponentPick.bot(weakest).setup(rating: 0, humanSide: .white, start: .standard, engines: engines)
        #expect(weak.strength == BotStrength(rating: weakest.rating, temperature: weakest.temperature, stockfishElo: weakest.stockfishElo))
        #expect(weak.stockfishElo == engines.stockfish.minElo)

        let built = OpponentPick.custom(catalogue.custom).setup(rating: 1230, humanSide: .white, start: .standard, engines: engines)
        #expect(built.botID == catalogue.custom.id)
        #expect(built.botName == catalogue.custom.name)
        #expect(built.rating == 1230)
        #expect(built.firstMove == nil)
        #expect(built.temperature == catalogue.custom.temperature)
        #expect(built.stockfishElo == engines.stockfish.minElo)
        #expect(built.isCustom)
        #expect(built.avatar == catalogue.custom.portraitUrl)
        // A rating outside the range the server offers is held to it, and
        // Stockfish to what it accepts.
        let over = OpponentPick.custom(catalogue.custom).setup(rating: 9000, humanSide: .white, start: .standard, engines: engines)
        #expect(over.rating == catalogue.custom.rating.max)
        #expect(over.stockfishElo == min(catalogue.custom.rating.max, engines.stockfish.maxElo))
        #expect(engines.stockfish.elo(forRating: 9000) == engines.stockfish.maxElo)
        #expect(engines.stockfish.elo(forRating: 2000) == 2000)

        #expect(SideChoice.white.resolved() == .white)
        #expect(SideChoice.black.resolved() == .black)
        #expect(SideChoice.random.resolved(coin: { true }) == .white)
        #expect(SideChoice.random.resolved(coin: { false }) == .black)
    }

    @Test func aGameSurvivesLeavingTheScreenAndRelaunchingTheApp() async throws {
        let folder = temporaryFolder()
        let server = PlayServer()
        let first = PlayModel(app: appModel(server), store: BotGameStore(folder: folder), cache: nil, engines: engines(StubBotEngine(kind: .maia, move: "e7e5")))
        await first.load()
        #expect(first.resumable == nil)
        let game = try #require(await first.start(setup(.white)))
        game.begin()
        #expect(game.play(move("e2e4")))
        #expect(await eventually { game.game.moves.count == 2 })
        #expect(game.play(move("g1f3")))
        // The screen goes away with the bot still to move.
        game.pause()
        first.refresh()
        #expect(first.resumable?.moves == ["e2e4", "e7e5", "g1f3"])

        // A new launch: another model, another engine, the same folder.
        let second = PlayModel(app: appModel(server), store: BotGameStore(folder: folder), cache: nil, engines: engines(StubBotEngine(kind: .stockfish, move: "b8c6")))
        await second.load()
        #expect(second.resumable?.setup.botName == "Maria")
        let resumed = try #require(await second.resume())
        #expect(resumed.game.moves.map(\.san) == ["e4", "e5", "Nf3"])
        #expect(resumed.game.botToMove)
        #expect(resumed.engineKind == .stockfish)
        resumed.begin()
        #expect(await eventually { resumed.game.moves.count == 4 })
        #expect(resumed.game.moves[3].san == "Nc6")
        #expect(resumed.game.humanToMove)

        // Played to its end, nothing is left to resume.
        resumed.resign()
        second.refresh()
        #expect(second.resumable == nil)
        #expect(await second.resume() == nil)
    }

    @Test func aGameInProgressCanBeGivenUp() async throws {
        let hub = PlayModel(app: appModel(PlayServer()), store: BotGameStore(folder: temporaryFolder()), cache: nil, engines: engines(StubBotEngine(move: "e7e5")))
        await hub.load()
        let game = try #require(await hub.start(setup(.white)))
        #expect(game.play(move("e2e4")))
        hub.refresh()
        #expect(hub.resumable != nil)
        hub.discardResumable()
        #expect(hub.resumable == nil)
        hub.refresh()
        #expect(hub.resumable == nil)
    }

    @Test func aBotThatCannotStartSaysSo() async {
        struct Failure: Error {}
        let hub = PlayModel(
            app: appModel(PlayServer()), store: BotGameStore(folder: temporaryFolder()), cache: nil,
            engines: { _ in
                BotEngineSelection(makeMaia: { throw Failure() }, makeStockfish: { throw Failure() }, loadBudget: .seconds(5), warmupBudget: .seconds(5))
            }
        )
        await hub.load()
        #expect(await hub.start(setup(.white)) == nil)
        #expect(hub.startFailure == "The bot could not start. Please try again.")
        #expect(!hub.isStarting)
    }
}
