import ChessCore
import Foundation
import Testing
@testable import ChessDesk

/// A server for the explorer that records what it is asked and answers from
/// the sample player's games, optionally late.
private nonisolated final class ExplorerServer: ExplorerAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [(path: [String], filters: ExplorerFilters)] = []
    private var delays: [String: Duration] = [:]
    private var failure: APIError?
    private var summary: ExplorerSummary?
    private var endsAt: Int?

    var requests: [(path: [String], filters: ExplorerFilters)] { lock.withLock { asked } }
    var paths: [String] { requests.map { $0.path.joined(separator: " ") } }

    func delay(_ path: String, by duration: Duration) { lock.withLock { delays[path] = duration } }
    func fail(_ error: APIError?) { lock.withLock { failure = error } }
    func answerSummary(_ summary: ExplorerSummary) { lock.withLock { self.summary = summary } }
    func endData(at plies: Int) { lock.withLock { endsAt = plies } }

    func explorerSummary(token: String) async throws -> ExplorerSummary {
        if let summary = lock.withLock({ summary }) { return summary }
        return await FixturePlayer.current.explorerSummary()
    }

    func explorerPosition(
        path: [String], filters: ExplorerFilters, games: Int?, token: String
    ) async throws -> ExplorerPosition {
        let (delay, failure, endsAt) = lock.withLock {
            asked.append((path, filters))
            return (delays[path.joined(separator: " ")], self.failure, self.endsAt)
        }
        if let delay { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        let position = try await FixturePlayer.current.explorerPosition(path: path, filters: filters, games: games)
        guard let endsAt, path.count >= endsAt else { return position }
        return ExplorerPosition(
            side: position.side, path: position.path, fen: position.fen, total: position.total, reaching: position.reaching,
            activeFilters: position.activeFilters, limit: position.limit, moves: position.moves, endOfData: true,
            games: position.games, insights: position.insights
        )
    }
}

@Suite(.samplePlayer()) @MainActor struct ExplorerModelTests {
    private func makeModel(onUnauthorized: @escaping () -> Void = {}) async -> (ExplorerModel, ExplorerServer) {
        let server = ExplorerServer()
        let model = ExplorerModel(api: server, token: "t", onUnauthorized: onUnauthorized)
        await model.load()
        return (model, server)
    }

    @Test func itOpensOnTheTreeOfTheWhiteGames() async throws {
        let (model, server) = await makeModel()
        #expect(model.phase == .ready)
        #expect(model.games(as: .white) == 30)
        #expect(model.games(as: .black) == 22)
        #expect(server.paths == [""])
        let position = try #require(model.position)
        #expect(model.isCurrent)
        #expect(position.total == 30)
        #expect(position.reaching == 30)
        // Every game starts with a move: the rows add up to the games.
        #expect(position.moves.map(\.san) == ["e4"])
        #expect(position.moves[0].games == 30)
        #expect(position.moves[0].wins + position.moves[0].draws + position.moves[0].losses == 30)
        #expect(position.moves[0].uci == "e2e4")
        #expect(position.games.count == 10)
        #expect(position.insights.mostPlayed?.line == "1.e4 e5 2.Nf3 Nc6 3.Bc4")
        #expect(model.sideToMove == .white)
        #expect(!model.canGoBack)
    }

    @Test func walkingDownAndBackAsksForEachPosition() async throws {
        let (model, server) = await makeModel()
        model.push("e4")
        await model.settled()
        model.push("e5")
        await model.settled()
        #expect(model.path == ["e4", "e5"])
        #expect(server.paths == ["", "e4", "e4 e5"])
        let position = try #require(model.position)
        #expect(position.path == ["e4", "e5"])
        #expect(position.reaching == 18)
        #expect(position.moves.map(\.san) == ["Nf3", "Bc4"])
        #expect(position.moves.map(\.games) == [17, 1])
        #expect(position.fen == "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        #expect(model.sideToMove == .white)
        #expect(model.onlyMove == nil)

        model.back()
        await model.settled()
        #expect(model.path == ["e4"])
        #expect(model.position?.path == ["e4"])
        #expect(model.sideToMove == .black)
        #expect(server.paths.last == "e4")

        // A line of the insights is opened in one step, and cut from the line strip.
        model.go(to: ["e4", "c5", "Nf3"])
        await model.settled()
        #expect(model.position?.reaching == 6)
        model.cut(to: 1)
        await model.settled()
        #expect(model.path == ["e4"])
        model.cut(to: 0)
        await model.settled()
        #expect(model.path.isEmpty)
        model.back()
        #expect(model.path.isEmpty)
    }

    @Test func filtersNarrowTheGamesAndKeepThePosition() async throws {
        let (model, server) = await makeModel()
        model.go(to: ["e4", "e5"])
        await model.settled()
        let all = try #require(model.position).reaching

        var filters = model.filters
        filters.timeClasses = ["BLITZ"]
        filters.rated = .rated
        model.apply(filters)
        await model.settled()
        #expect(model.path == ["e4", "e5"])
        #expect(server.requests.last?.filters.timeClasses == ["BLITZ"])
        #expect(server.requests.last?.filters.rated == .rated)
        let narrowed = try #require(model.position)
        #expect(narrowed.activeFilters == 2)
        #expect(narrowed.reaching < all)
        #expect(narrowed.total < 30)
        #expect(narrowed.games.allSatisfy { $0.timeClass == "BLITZ" && $0.rated })

        // The same filters again ask nothing.
        let asked = server.requests.count
        model.apply(filters)
        #expect(server.requests.count == asked)

        model.clearFilters()
        await model.settled()
        #expect(model.filters.activeCount == 0)
        #expect(model.position?.reaching == all)
        #expect(model.path == ["e4", "e5"])

        // The other colour is another tree: the walk starts again.
        model.choose(side: .black)
        await model.settled()
        #expect(model.path.isEmpty)
        #expect(model.position?.side == "black")
        #expect(model.position?.total == 22)
        #expect(model.position?.moves.map(\.san) == ["e4", "d4", "c4"])
        #expect(server.requests.last?.filters.side == .black)
    }

    /// A slow answer for a position the player has left is not shown.
    @Test func aLateAnswerDoesNotReplaceTheCurrentPosition() async throws {
        let (model, server) = await makeModel()
        server.delay("e4", by: .milliseconds(150))
        model.push("e4")
        #expect(model.isLoadingPosition)
        #expect(!model.isCurrent)
        // The position before stays on screen meanwhile.
        #expect(model.position?.path == [])
        model.go(to: ["e4", "c5"])
        await model.settled()
        #expect(model.position?.path == ["e4", "c5"])
        try? await Task.sleep(for: .milliseconds(220))
        #expect(model.position?.path == ["e4", "c5"])
        #expect(model.isCurrent)
    }

    @Test func aFailureKeepsThePlaceAndCanBeTriedAgain() async throws {
        var expired = 0
        let (model, server) = await makeModel(onUnauthorized: { expired += 1 })
        server.fail(.offline)
        model.push("e4")
        await model.settled()
        #expect(model.positionFailure == APIError.offline.message)
        #expect(model.path == ["e4"])
        #expect(!model.isLoadingPosition)
        server.fail(nil)
        model.retry()
        await model.settled()
        #expect(model.positionFailure == nil)
        #expect(model.position?.path == ["e4"])

        server.fail(.server(status: 401, code: "unauthorized", message: "Sign in to continue."))
        model.push("e5")
        await model.settled()
        #expect(expired == 1)
    }

    @Test func theStoredOpeningMovesEndSomewhere() async throws {
        let (model, server) = await makeModel()
        server.endData(at: 2)
        model.go(to: ["e4", "e5"])
        await model.settled()
        #expect(model.position?.endOfData == true)
        let asked = server.requests.count
        model.push("Nf3")
        #expect(model.path == ["e4", "e5"])
        #expect(server.requests.count == asked)
    }

    @Test func aPlayerWithOnlyBlackGamesOpensOnBlack() async throws {
        let server = ExplorerServer()
        server.answerSummary(ExplorerSummary(white: 0, black: 22, imported: 22, limit: 100, capped: false, hasLinkedAccount: true))
        let model = ExplorerModel(api: server, token: "t")
        await model.load()
        #expect(model.side == .black)
        #expect(server.requests.first?.filters.side == .black)

        // No game at all: nothing is asked beyond the summary.
        let empty = ExplorerServer()
        empty.answerSummary(ExplorerSummary(white: 0, black: 0, imported: 0, limit: 100, capped: false, hasLinkedAccount: false))
        let nothing = ExplorerModel(api: empty, token: "t")
        await nothing.load()
        #expect(nothing.phase == .ready)
        #expect(nothing.summary?.isEmpty == true)
        #expect(empty.requests.isEmpty)
    }

    @Test func theExplorerThatDoesNotLoadSaysWhy() async {
        final class Down: ExplorerAPI, @unchecked Sendable {
            func explorerSummary(token: String) async throws -> ExplorerSummary { throw APIError.offline }
        }
        let model = ExplorerModel(api: Down(), token: "t")
        await model.load()
        #expect(model.phase == .failed(APIError.offline.message))
    }
}

@Suite struct ExplorerFiltersTests {
    /// The count of the site's `lib/explorer/filter-count.ts`: one per group.
    @Test func eachGroupOfFiltersCountsOnce() {
        var filters = ExplorerFilters()
        #expect(filters.activeCount == 0)
        filters.side = .black
        #expect(filters.activeCount == 0)
        filters.timeClasses = ["BLITZ", "RAPID"]
        #expect(filters.activeCount == 1)
        filters.rated = .casual
        filters.dateFrom = "2026-01-01"
        filters.dateTo = "2026-06-30"
        #expect(filters.activeCount == 3)
        filters.opponentMax = 1200
        filters.source = .chesscom
        #expect(filters.activeCount == 5)
        #expect(filters.cleared == ExplorerFilters(side: .black))
    }

    @Test func aDayIsWrittenAsTheAPIReadsIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 0, minute: 30)))
        #expect(ExplorerFilters.day(date, calendar: calendar) == "2026-03-07")
        #expect(ExplorerFilters.date(day: "2026-03-07", calendar: calendar).map { ExplorerFilters.day($0, calendar: calendar) } == "2026-03-07")
        #expect(ExplorerFilters.date(day: "soon") == nil)
        let pattern = "^\\d{4}-\\d{2}-\\d{2}$"
        #expect(ExplorerFilters.day(.now).range(of: pattern, options: .regularExpression) != nil)
    }

    @Test func scoresAreColouredAsOnTheSite() {
        func move(_ score: Double) -> ExplorerPosition.Move {
            .init(san: "e4", uci: "e2e4", games: 10, wins: 5, draws: 0, losses: 5, score: score, sampleGameId: "g")
        }
        #expect(move(0.55).tone == .good)
        #expect(move(0.5).tone == .even)
        #expect(move(0.48).tone == .even)
        #expect(move(0.479).tone == .poor)
        #expect(move(0.774).percent == 77)
    }

    /// The sample explorer follows the site's arithmetic: the free cap, the
    /// rows of a position, an illegal line.
    @Test func theSampleExplorerAnswersLikeTheServer() async throws {
        let player = FixturePlayer(premium: false)
        let summary = await player.explorerSummary()
        #expect(summary.white == 30)
        #expect(summary.black == 22)
        #expect(summary.limit == 100)
        #expect(!summary.capped)
        #expect(!summary.isEmpty)
        let premium = await FixturePlayer(premium: true).explorerSummary()
        #expect(premium.limit == nil)

        let root = try await player.explorerPosition(path: [], filters: ExplorerFilters(), games: 50)
        #expect(root.games.count == 30)
        #expect(root.limit == 100)
        #expect(!root.endOfData)
        let italian = try await player.explorerPosition(path: ["e4", "e5", "Nf3", "Nc6"], filters: ExplorerFilters(), games: nil)
        #expect(italian.moves.map(\.san) == ["Bc4", "Bb5"])
        #expect(italian.moves[0].games == 11)
        #expect(italian.moves[0].wins == 8)
        #expect(abs(italian.moves[0].score - 8.5 / 11) < 0.0001)
        #expect(italian.moves[1].sampleGameId.hasPrefix("sample-game-"))
        #expect(italian.reaching == 12)
        // The end of a short line: games reached it, no move follows.
        let end = try await player.explorerPosition(path: ["e4", "e5", "Bc4", "Nf6", "d3", "Bc5"], filters: ExplorerFilters(), games: nil)
        #expect(end.moves.isEmpty)
        #expect(end.reaching == 1)
        var lichess = ExplorerFilters()
        lichess.source = .lichess
        let narrowed = try await player.explorerPosition(path: [], filters: lichess, games: 50)
        #expect(narrowed.games.allSatisfy { $0.source == "LICHESS" })
        #expect(narrowed.total == narrowed.games.count)
        #expect(narrowed.activeFilters == 1)
        await #expect(throws: APIError.self) {
            _ = try await player.explorerPosition(path: ["e4", "Ke2"], filters: ExplorerFilters(), games: nil)
        }
    }
}
