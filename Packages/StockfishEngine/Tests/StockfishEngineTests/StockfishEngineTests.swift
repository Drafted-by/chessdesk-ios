import Foundation
import Testing
@testable import StockfishEngine

/// The network is fetched by scripts/fetch-nnue.sh into the app's resources.
private let network = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "ChessDesk/Resources/Engine/\(StockfishEngine.networkName)")

@Suite(.serialized) struct StockfishEngineTests {
    @Test func parsesInfoLines() {
        let cp = StockfishEngine.parseInfo(
            "info depth 12 seldepth 16 multipv 1 score cp 31 nodes 9000 nps 500000 pv e2e4 e7e5 g1f3"
        )
        #expect(cp == EngineEvaluation(centipawns: 31, mate: nil, depth: 12, principalVariation: ["e2e4", "e7e5", "g1f3"]))
        let mate = StockfishEngine.parseInfo("info depth 3 score mate -2 pv a1a2")
        #expect(mate?.mate == -2)
        #expect(mate?.comparable == -9998)
        #expect(StockfishEngine.parseInfo("info depth 9 score cp 50 lowerbound pv e2e4") == nil)
        #expect(StockfishEngine.parseInfo("info string NNUE evaluation using nn.nnue") == nil)
        #expect(StockfishEngine.parseInfo("bestmove e2e4 ponder e7e5") == nil)
    }

    /// The expectations of the site's `stockfish-bot-engine.test.ts`.
    @Test func readsTheBestMoveLine() {
        #expect(StockfishEngine.parseBestMove("bestmove e2e4 ponder e7e5") == "e2e4")
        #expect(StockfishEngine.parseBestMove("bestmove g1f3") == "g1f3")
        #expect(StockfishEngine.parseBestMove("bestmove (none)") == nil)
        #expect(StockfishEngine.parseBestMove("info depth 3 score cp 10 pv e2e4") == nil)
    }

    @Test func refusesToStartWithoutItsNetwork() async {
        await #expect(throws: EngineError.networkMissing("missing.nnue")) {
            try await StockfishEngine.shared.start(network: URL(fileURLWithPath: "/nonexistent/missing.nnue"))
        }
    }

    @Test func findsMateAndJudgesMaterial() async throws {
        try #require(FileManager.default.fileExists(atPath: network.path), "run scripts/fetch-nnue.sh first")
        let engine = StockfishEngine.shared
        try await engine.start(network: network)

        // Back-rank mate in one: Re8#.
        let mate = try await engine.evaluate(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1")
        #expect(mate.mate == 1)
        #expect(mate.bestMove == "e1e8")

        // The start position is about level.
        let start = try await engine.evaluate(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        #expect(abs(start.comparable) < 120)
        #expect(start.depth >= 8)

        // A queen up is winning by a wide margin.
        let queenUp = try await engine.evaluate(fen: "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        #expect(queenUp.comparable > 500)

        // Held to a rating, it still answers with a legal move, and quickly.
        let limited = try await engine.bestMove(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", limitedTo: 400, moveTime: .milliseconds(300)
        )
        #expect(limited?.count == 4)
        let stalemated = try await engine.bestMove(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", limitedTo: 1500, moveTime: .milliseconds(100))
        #expect(stalemated == nil)
        // The limit does not outlive the bot's move: the mate is still found at once.
        let after = try await engine.evaluate(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1")
        #expect(after.mate == 1)

        // Searches asked at the same time are answered one after the other.
        async let first = engine.evaluate(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", depth: 6)
        async let second = engine.evaluate(fen: "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", depth: 6)
        let (one, two) = try await (first, second)
        #expect(one.mate == 1)
        #expect(two.mate == nil)
    }
}
