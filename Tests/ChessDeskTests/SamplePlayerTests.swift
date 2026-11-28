import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// The sample data is one world: a guest is a guest everywhere, and the sample
// player's home, games, repertoire and explorer speak of the same games.

@Suite struct SamplePlayerTests {
    private let guest = FixtureAPI(delay: .zero)
    private let player = FixturePlayer()
    private var api: FixtureAPI { FixtureAPI(delay: .zero, player: player) }

    private func isUnauthorized(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            return false
        } catch let failure as APIError {
            return failure.isUnauthorized
        } catch {
            return false
        }
    }

    /// Without the sample player, every route that needs an account says so:
    /// the repertoires and the explorer too.
    @Test func aGuestIsAGuestEverywhere() async throws {
        let guest = guest
        #expect(await isUnauthorized { _ = try await guest.me(token: "t") })
        #expect(await isUnauthorized { _ = try await guest.home(token: "t") })
        #expect(await isUnauthorized { _ = try await guest.games(cursor: nil, token: "t") })
        #expect(await isUnauthorized { _ = try await guest.due(token: "t") })
        #expect(await isUnauthorized { _ = try await guest.repertoires(token: "t") })
        #expect(await isUnauthorized { _ = try await guest.repertoire(id: "sample-italian", token: "t") })
        #expect(await isUnauthorized { _ = try await guest.repertoireSession(id: "sample-italian", mode: nil, token: "t") })
        #expect(await isUnauthorized { _ = try await guest.explorerSummary(token: "t") })
        #expect(await isUnauthorized { _ = try await guest.explorerPosition(path: [], filters: ExplorerFilters(), games: nil, token: "t") })
        #expect(await isUnauthorized { try await guest.sendGrades(deck: "repertoire:sample-italian", grades: [], token: "t") })
        #expect(await isUnauthorized { _ = try await guest.courseSession(slug: "practical-caro-kann", mode: .review, line: nil, token: "t") })
        // What is open to a guest still is.
        #expect(try await guest.courses(token: nil).allSatisfy { $0.enrollment == nil })
        #expect(try await guest.puzzleOverview(token: nil).free.puzzles > 0)
    }

    @Test @MainActor func aGuestOnSampleDataHasNoPlayerToken() async {
        let app = AppModel(backend: .sampleData, api: guest, makeTokenStore: { _ in MemoryTokenStore() })
        await app.restoreSession()
        #expect(!app.isSignedIn)
        #expect(app.playerToken == nil)
        let signedIn = AppModel(backend: .sampleData, api: api, makeTokenStore: { _ in MemoryTokenStore(FixturePlayer.token) })
        await signedIn.restoreSession()
        #expect(signedIn.isSignedIn)
        #expect(signedIn.playerToken == FixturePlayer.token)
    }

    /// One set of games behind the list, the home, the explorer and the repertoire's check.
    @Test func theGamesAreTheSameEverywhere() async throws {
        let api = api
        var listed: [GameSummary] = []
        var cursor: String?
        repeat {
            let page = try await api.games(cursor: cursor, token: "t")
            listed += page.games
            cursor = page.nextCursor
        } while cursor != nil
        #expect(listed.count == 52)
        #expect(Set(listed.map(\.id)).count == 52)
        #expect(listed.map(\.playedAt) == listed.map(\.playedAt).sorted(by: >))
        // The player is the same person in every game, on the accounts that are linked.
        let accounts = try await api.accounts(token: "t")
        #expect(Set(accounts.map(\.username)) == [FixtureData.handle])
        #expect(Set(listed.map(\.source)) == Set(accounts.map(\.provider.rawValue)))
        #expect(listed.allSatisfy { ($0.userColor == "white" ? $0.white : $0.black) == FixtureData.handle })

        let home = try await api.home(token: "t")
        #expect(home.totalGames == listed.count)
        let summary = try await api.explorerSummary(token: "t")
        #expect(summary.imported == listed.count)
        #expect(summary.white + summary.black == listed.count)
        #expect(summary.limit == (try await api.me(token: "t")).freeLimits.explorerGames)
        #expect(summary.hasLinkedAccount)
    }

    /// Every game is a whole, legal game that the game screen replays.
    @Test func everyGameOpensAndReplays() async throws {
        let api = api
        for game in player.sampleGames {
            let detail = try await api.game(id: game.summary.id, token: "t")
            let line = GameLine(pgn: detail.pgn)
            #expect(line.moves.count == detail.ply, "\(detail.id) replays whole")
            #expect(detail.ply == game.moves.count && detail.ply >= 20, "\(detail.id) is a game, not an opening")
            #expect(Array(line.moves.map(\.san).prefix(game.line.count)) == game.line, "\(detail.id) starts with its opening")
            #expect(line.headers["Result"] == detail.result)
            #expect(detail.opening == game.summary.opening)
        }
        await #expect(throws: APIError.self) { _ = try await api.game(id: "nobody", token: "t") }
    }

    /// A game named by the home, the mistakes, the Daily 5 or a pattern is a
    /// game of the list, against the opponent that is named.
    @Test func whatTheHomeNamesIsInTheGames() async throws {
        let api = api
        let games = Dictionary(uniqueKeysWithValues: player.sampleGames.map { ($0.summary.id, $0) })
        func expect(_ id: String?, opponent: String? = nil, _ place: String) {
            guard let id else { return }
            let game = games[id]
            #expect(game != nil, "\(place) names \(id)")
            if let opponent { #expect(game?.opponent == opponent, "\(place) names \(opponent)") }
        }
        let home = try await api.home(token: "t")
        let review = try #require(home.today.first { $0.target.kind.value == .review })
        let newest = try #require(player.sampleGames.first)
        // "Review your last game" is the newest one, and it was lost to who the step says.
        #expect(review.target.gameId == newest.summary.id)
        #expect(newest.result == "loss")
        #expect(review.detail.contains("Lost to \(newest.opponent)"))
        expect(home.pulse.bestWin?.gameId, opponent: home.pulse.bestWin?.opponent, "Best win")
        #expect(home.pulse.bestWin.flatMap { games[$0.gameId] }?.result == "win")
        expect(home.onboarding.firstReport?.blunder?.gameId, opponent: home.onboarding.firstReport?.blunder?.opponent, "First report")
        for mistake in try await api.mistakes(token: "t").due { expect(mistake.gameId, opponent: mistake.opponent, "Mistake \(mistake.id)") }
        for item in try await api.daily(again: false, token: "t").items { expect(item.gameId, "Daily 5") }
        for mistake in try await api.patternDrill(key: "hanging", token: "t").mistakes {
            expect(mistake.gameId, opponent: mistake.opponent, "Pattern drill")
        }
    }

    /// A game opened from the explorer or from the repertoire's games check is there.
    @Test func gamesOfTheExplorerAndOfTheRepertoireCheckOpen() async throws {
        let premium = FixtureAPI(delay: .zero, player: FixturePlayer(premium: true))
        #expect(try await premium.me(token: "t").access.premium)
        for side in [Side.white, .black] {
            let root = try await premium.explorerPosition(path: [], filters: ExplorerFilters(side: side), games: 50, token: "t")
            #expect(!root.games.isEmpty)
            for summary in root.games {
                let detail = try await premium.game(id: summary.id, token: "t")
                #expect(detail.white == summary.white && detail.black == summary.black && detail.result == summary.result)
            }
            for move in root.moves { _ = try await premium.game(id: move.sampleGameId, token: "t") }
        }
        let check = try await premium.repertoireAdherence(id: "sample-italian", token: "t")
        #expect(!check.games.isEmpty)
        for row in check.games {
            let detail = try await premium.game(id: row.gameId, token: "t")
            #expect([detail.white, detail.black].contains(row.opponent))
            #expect(detail.userColor == "white")
        }
        // The walk of the explorer ends in games that start with the moves walked.
        let italian = try await premium.explorerPosition(
            path: ["e4", "e5", "Nf3", "Nc6", "Bc4"], filters: ExplorerFilters(), games: 50, token: "t"
        )
        for summary in italian.games {
            let moves = GameLine(pgn: try await premium.game(id: summary.id, token: "t").pgn).moves.map(\.san)
            #expect(Array(moves.prefix(5)) == ["e4", "e5", "Nf3", "Nc6", "Bc4"])
        }
    }

    /// What is due is one summary: the course the player follows and the
    /// repertoire, the same numbers as on their own screens, and the step of the plan.
    @Test func whatIsDueAgreesAcrossTheScreens() async throws {
        let api = api
        let due = try await api.due(token: "t")
        try #require(try Contract.problems(in: try Contract.json(due), against: "DueSummary") == [])
        #expect(due.decks.map(\.kind) == ["course", "repertoire"])
        let list = try await api.repertoires(token: "t")
        let course = try #require(try await api.courses(token: "t").first { $0.slug == FixturePlayer.courseSlug })
        #expect(course.enrollment == .active)
        #expect(due.decks[0].progress == course.progress)
        #expect(due.decks[0].name == course.title)
        #expect(due.decks[1].progress == list.repertoires.first?.progress)
        #expect(due.decks[1].name == list.repertoires.first?.name)
        #expect(due.totalDue == (course.progress?.dueMoves ?? 0) + list.totalDue)
        #expect(due.totalDue == 7)
        #expect(due.top == FixturePlayer.courseDeck)
        // Both rows of Today's due card.
        let rows = DueRow.rows(due: due, courses: try await api.courses(token: "t"))
        #expect(rows.count == 2)

        // The plan carries the step, where the server puts it, and it opens the top deck.
        let home = try await api.home(token: "t")
        #expect(home.today.map(\.key) == ["daily", "review", "path", "mistakes", "repertoire"])
        let step = try #require(home.today.last)
        #expect(step.detail == "7 moves are due for spaced repetition")
        #expect(HomeRouter.route(step.target) == .courseReview(slug: FixturePlayer.courseSlug))

        // The course is reviewed: its page, the summary and the plan follow.
        let page = try await api.course(slug: FixturePlayer.courseSlug, token: "t")
        #expect(page.progress.dueLines == 1)
        let review = try await api.courseSession(slug: FixturePlayer.courseSlug, mode: .review, line: nil, token: "t")
        #expect(review.mode == .review)
        let item = try #require(review.review.first)
        let line = try #require(review.lines.first { $0.id == item.lineId })
        #expect(item.test.count == 4)
        #expect(item.test.allSatisfy { line.steps[$0].mine })
        let grades = item.test.map { MoveGrade(fen: line.steps[$0].fenBefore, uci: line.steps[$0].uci, grade: .good) }
        try await api.sendGrades(deck: review.deck, grades: grades, token: "t")
        #expect(try await api.course(slug: FixturePlayer.courseSlug, token: "t").progress.dueLines == 0)
        #expect(try await api.courseSession(slug: FixturePlayer.courseSlug, mode: .review, line: nil, token: "t").review.isEmpty)
        let after = try await api.due(token: "t")
        #expect(after.totalDue == 3)
        #expect(after.top == "repertoire:sample-italian")
        let next = try #require(try await api.home(token: "t").today.first { $0.key == "repertoire" })
        #expect(HomeRouter.route(next.target) == .repertoire(id: "sample-italian"))

        // Then the repertoire: nothing is due any more and the step leaves the plan.
        let session = try await api.repertoireSession(id: "sample-italian", mode: .review, token: "t")
        let good = session.review.flatMap { item -> [MoveGrade] in
            guard let line = session.lines.first(where: { $0.id == item.lineId }) else { return [] }
            return item.test.map { MoveGrade(fen: line.steps[$0].fenBefore, uci: line.steps[$0].uci, grade: .good) }
        }
        try await api.sendGrades(deck: session.deck, grades: good, token: "t")
        #expect(try await api.due(token: "t").totalDue == 0)
        #expect(try await api.home(token: "t").today.map(\.key) == ["daily", "review", "path", "mistakes", "puzzles"])
    }

    /// The fixtures the player answers with have the shapes of the contract.
    @Test func theSamplePlayerAnswersHaveTheShapesOfTheContract() async throws {
        let api = api
        func expectContract(_ value: some Encodable, _ schema: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
            let problems = try Contract.problems(in: try Contract.json(value), against: schema)
            #expect(problems == [], "\(schema)", sourceLocation: sourceLocation)
        }
        try expectContract(try await api.games(cursor: nil, token: "t"), "GamesPage")
        try expectContract(try await api.home(token: "t"), "Home")
        try expectContract(try await api.settings(token: "t"), "Settings")
        try expectContract(try await api.courseSession(slug: FixturePlayer.courseSlug, mode: .review, line: nil, token: "t"), "CourseSession")
        let settings = try await api.settings(token: "t")
        #expect([16, 22, 28].contains(settings.preferences.engineDepth))
        #expect((1...5).contains(settings.preferences.engineLines))
    }
}
