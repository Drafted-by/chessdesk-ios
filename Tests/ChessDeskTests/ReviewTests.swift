import ChessCore
import Foundation
import Testing
@testable import ChessDesk

/// Test stubs implement what they exercise; the games and mistakes calls
/// default to "not signed in".
extension ChessDeskAPI {
    private var notStubbed: APIError { .server(status: 401, code: "unauthorized", message: "Not stubbed.") }
    func accounts(token: String) async throws -> [LinkedAccount] { throw notStubbed }
    func linkAccount(_ provider: GameProvider, username: String, token: String) async throws -> LinkedAccount { throw notStubbed }
    func unlinkAccount(_ provider: GameProvider, token: String) async throws { throw notStubbed }
    func importGames(_ provider: GameProvider, mode: ImportMode, cursor: String?, token: String) async throws -> ImportChunk { throw notStubbed }
    func games(cursor: String?, token: String) async throws -> GamesPage { throw notStubbed }
    func game(id: String, token: String) async throws -> GameDetail { throw notStubbed }
    func setStar(game: String, starred: Bool, token: String) async throws { throw notStubbed }
    func saveReview(game: String, review: GameReview, token: String) async throws { throw notStubbed }
    func mistakes(token: String) async throws -> MistakeQueue { throw notStubbed }
    func recordMistakeAttempt(_ mistake: String, result: MistakeResult, token: String) async throws -> MistakeAttempt { throw notStubbed }
}

/// The same expectations as the site's `win-chance.test.ts` and `classify.test.ts`.
@Suite struct ReviewMathTests {
    private func judge(_ before: Double, _ after: Double, top: Bool = false, ply: Int = 20, cp: Double? = 100,
                       second: Double? = nil, material: Int? = nil) -> MoveClass {
        ReviewMath.classify(.init(winBefore: before, winAfter: after, isTopMove: top, ply: ply,
                                  evalCentipawns: cp, secondBestWin: second, materialDelta: material))
    }

    @Test func winPercentFollowsTheLichessCurve() {
        #expect(abs(ReviewMath.winPercent(centipawns: 0) - 50) < 1e-9)
        #expect(ReviewMath.winPercent(centipawns: 1000) > 95)
        #expect(ReviewMath.winPercent(centipawns: 1000) < 100)
        #expect(abs(ReviewMath.winPercent(centipawns: -300) - (100 - ReviewMath.winPercent(centipawns: 300))) < 1e-9)
        #expect(ReviewMath.winPercent(centipawns: 5000) == ReviewMath.winPercent(centipawns: 1000))
    }

    @Test func aMateIsTheCeilingNotAHardHundred() {
        #expect(abs(ReviewMath.winPercent(centipawns: nil, mate: 3) - 97.5447) < 0.001)
        #expect(abs(ReviewMath.winPercent(centipawns: nil, mate: -2) - 2.4553) < 0.001)
        #expect(ReviewMath.winPercent(centipawns: nil, mate: 1) == ReviewMath.winPercent(centipawns: nil, mate: 9))
        #expect(ReviewMath.winPercent(centipawns: nil, mate: 0) == 0)
        #expect(ReviewMath.winPercent(centipawns: nil, mate: nil) == 50)
    }

    @Test func lossesAreNamedByTheirSize() {
        #expect(judge(70, 45) == .blunder)
        #expect(judge(60, 48) == .mistake)
        #expect(judge(55, 49) == .inaccuracy)
        #expect(judge(50, 49, top: true) == .best)
        #expect(judge(53, 50) == .good)
        #expect(judge(51, 50.8, ply: 4, cp: 20) == .book)
        #expect(judge(60, 30, ply: 4, cp: 20) == .blunder)
    }

    @Test func greatIsTheOnlyMoveAndBrilliantASoundSacrifice() {
        #expect(judge(60, 60, top: true, second: 40) == .great)
        #expect(judge(60, 60, top: true, second: 50) == .best)
        #expect(judge(60, 60, top: true, second: nil) == .best)
        #expect(judge(60, 59, top: true, material: -3) == .brilliant)
        // A sacrifice that loses is not brilliant; nor is a trade.
        #expect(judge(40, 40, top: true, material: -3) == .best)
        #expect(judge(60, 59, top: true, material: 0) == .best)
        // Not the engine's move and a real loss: never promoted.
        #expect(judge(60, 52, material: -3) == .inaccuracy)
    }

    @Test func accuracyPunishesTheWorstMoves() {
        #expect(ReviewMath.moveAccuracy(winBefore: 50, winAfter: 50) > 99)
        #expect(ReviewMath.moveAccuracy(winBefore: 70, winAfter: 40) < 40)
        #expect(ReviewMath.standardDeviation([50, 50, 50, 50]) == 0)
        #expect(abs(ReviewMath.standardDeviation([0, 100]) - 50) < 1e-9)
        #expect(abs(ReviewMath.harmonicMean([100, 100, 100]) - 100) < 1e-9)
        #expect(ReviewMath.harmonicMean([100, 100, 100, 100, 20]) < 70)
        #expect(ReviewMath.harmonicMean([0, 100]).isFinite)
        #expect(ReviewMath.blendedAccuracy([100, 100, 100, 100], weights: [1, 1, 1, 1]) > 99)
        #expect(ReviewMath.blendedAccuracy([100, 100, 100, 100, 20], weights: [1, 1, 1, 1, 1]) < 84)
        #expect(ReviewMath.blendedAccuracy([], weights: []) == 0)
    }

    @Test func thereIsOneVolatilityWeightPerMove() {
        let quiet = Array(repeating: 50.0, count: 41)
        let weights = ReviewMath.volatilityWeights(quiet)
        #expect(weights.count == 40)
        #expect(weights.allSatisfy { $0 == 0.5 })
        let wild = (0..<31).map { $0.isMultiple(of: 2) ? 10.0 : 90.0 }
        let swings = ReviewMath.volatilityWeights(wild)
        #expect(swings.count == 30)
        #expect(swings.max() ?? 0 <= 12)
        #expect(ReviewMath.volatilityWeights([50]).isEmpty)
    }
}

@Suite struct GameLineTests {
    static let scholars = """
    [Event "Casual"]
    [White "Ana"]
    [Black "Ben"]
    [Result "1-0"]

    1. e4 {best by test} e5 2. Bc4 Nc6 (2... Nf6 3. d3) 3. Qh5 $2 Nf6?? 4.Qxf7# 1-0
    """

    @Test func readsTheMovesAndDropsTheRest() {
        let line = GameLine(pgn: Self.scholars)
        #expect(line.moves.map(\.san) == ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"])
        #expect(line.moves.map(\.ply) == [1, 2, 3, 4, 5, 6, 7])
        #expect(line.moves.last?.side == .white)
        #expect(line.headers["White"] == "Ana")
        #expect(line.fens.count == 8)
        #expect(Position(fen: line.fen(atPly: 7))?.isCheckmate == true)
        #expect(line.fen(atPly: 0) == Position.startFEN)
    }

    @Test func castlingWithZerosAndAnIllegalMoveEndsTheLine() {
        let line = GameLine(pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. Qxh7 d6")
        #expect(line.moves.map(\.san) == ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "O-O", "Nf6"])
    }

    @Test func aGameFromAPositionStartsThere() {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 30"
        let line = GameLine(pgn: "[SetUp \"1\"]\n[FEN \"\(fen)\"]\n\n30... Kd7 31. e4")
        #expect(line.startFEN == fen)
    }
}

@Suite struct ReviewBuilderTests {
    /// Every position equal, the engine agreeing with each move played.
    private func agreeing(_ line: GameLine) -> [PositionEval] {
        line.fens.enumerated().map { index, _ in
            // Evaluations are the side to move's: an equal game alternates +15 and -15.
            PositionEval(centipawns: index.isMultiple(of: 2) ? 15 : -15, mate: nil, bestSAN: index < line.moves.count ? line.moves[index].san : "")
        }
    }

    @Test func aGamePlayedLikeTheEngineIsNearPerfect() {
        let line = GameLine(pgn: "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5")
        let review = ReviewBuilder.build(line: line, evals: agreeing(line), depth: 18)
        #expect(review.moves.count == 12)
        #expect(review.whiteAccuracy > 98)
        #expect(review.blackAccuracy > 98)
        #expect(review.moves.allSatisfy { !$0.classification.isError })
        #expect(review.moves[0].color == "w")
        #expect(review.moves[1].color == "b")
    }

    @Test func aBlunderIsFoundAndCostsAccuracy() {
        let line = GameLine(pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Ng5 d5 5. exd5 Nxd5 6. Nxf7 Kxf7")
        var evals = agreeing(line)
        // After Black's 5...Nxd5 (position 10, White to move) White is winning;
        evals[10] = PositionEval(centipawns: 250, mate: nil, bestSAN: "Nxf7")
        // White plays it; then Black, to move, is losing by as much.
        evals[11] = PositionEval(centipawns: -250, mate: nil, bestSAN: "Kxf7")
        let review = ReviewBuilder.build(line: line, evals: evals, depth: 18)
        // Black's 5...Nxd5 took an equal position to a lost one.
        let blunder = review.moves[9]
        #expect(blunder.san == "Nxd5")
        #expect(blunder.classification == .blunder || blunder.classification == .mistake)
        #expect(blunder.winLoss > 10)
        #expect(review.blackAccuracy < review.whiteAccuracy)
        // White's view after the move: White is better.
        #expect((blunder.evalCp ?? 0) > 200)
    }

    @Test func checkmateIsReadFromTheRulesNotTheEngine() {
        let line = GameLine(pgn: GameLineTests.scholars)
        var evals = agreeing(line)
        evals[6] = PositionEval(centipawns: nil, mate: 1, bestSAN: "Qxf7#")
        evals[7] = .unknown
        let review = ReviewBuilder.build(line: line, evals: evals, depth: 18)
        let mate = review.moves[6]
        #expect(mate.san == "Qxf7#")
        #expect(mate.mate == 0)
        #expect(!mate.classification.isError)
    }

    @Test func theReviewerAsksTheEngineForEveryLivePosition() async throws {
        let line = GameLine(pgn: GameLineTests.scholars)
        let asked = Counter()
        let reviewer = GameReviewer(analyse: { fen in
            await asked.add()
            return PositionEval(centipawns: 20, mate: nil)
        })
        let done = Counter()
        let review = try await reviewer.review(line) { _ in await done.add() }
        #expect(await asked.value == 7) // the mated position is not searched
        #expect(await done.value == 8)
        #expect(review.moves.count == 7)
        #expect(review.depth == 18)
    }

    @Test func aReviewIsEncodedAsTheContractRequires() throws {
        let line = GameLine(pgn: GameLineTests.scholars)
        let review = ReviewBuilder.build(line: line, evals: agreeing(line), depth: 18, now: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try APICoding.encoder.encode(SaveReviewRequest(review: review))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(object["review"] as? [String: Any])
        #expect(body["computedAt"] as? String == "2027-01-15T08:00:00.000Z")
        #expect(body["version"] as? Int == 1)
        let moves = try #require(body["moves"] as? [[String: Any]])
        let required: Set = ["ply", "san", "color", "evalCp", "mate", "bestSan", "cpl", "winLoss", "classification"]
        #expect(moves.allSatisfy { Set($0.keys) == required })
        // And it reads back.
        let decoded = try APICoding.decoder.decode(SaveReviewRequest.self, from: data)
        #expect(decoded.review.moves.count == 7)
    }
}

private actor Counter {
    private(set) var value = 0
    func add() { value += 1 }
}
