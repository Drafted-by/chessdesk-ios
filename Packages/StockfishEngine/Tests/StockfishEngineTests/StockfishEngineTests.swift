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

        // Searches asked at the same time are answered one after the other.
        async let first = engine.evaluate(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", depth: 6)
        async let second = engine.evaluate(fen: "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", depth: 6)
        let (one, two) = try await (first, second)
        #expect(one.mate == 1)
        #expect(two.mate == nil)
    }
}

/// The live search of the analysis board. Nested in the suite above, so they
/// share its order: one engine, one test at a time.
extension StockfishEngineTests {
    @Suite struct LiveSearchTests {
        private func startedEngine() async throws -> StockfishEngine {
            try #require(FileManager.default.fileExists(atPath: network.path), "run scripts/fetch-nnue.sh first")
            let engine = StockfishEngine.shared
            try await engine.start(network: network)
            return engine
        }

        @Test func reportsEachDepthWithItsLinesBestFirst() async throws {
            let engine = try await startedEngine()
            var depths: [Int] = []
            var last: LiveSearchUpdate?
            for try await update in engine.liveSearch(fen: Position.italian, lines: 3, maxDepth: 10) {
                depths.append(update.depth)
                last = update
            }
            let final = try #require(last)
            #expect(final.depth == 10)
            #expect(final.lines.count == 3)
            #expect(final.lines.map(\.comparable) == final.lines.map(\.comparable).sorted(by: >))
            #expect(depths == depths.sorted())
            #expect(Set(depths).count >= 5)
        }

        @Test func endingTheStreamStopsAnInfiniteSearchAndFreesTheEngine() async throws {
            let engine = try await startedEngine()
            let clock = ContinuousClock()
            let reader = Task {
                var count = 0
                for try await _ in engine.liveSearch(fen: Position.italian, lines: 2) {
                    count += 1
                }
                return count
            }
            try await Task.sleep(for: .milliseconds(600))
            let stopped = clock.now
            reader.cancel()
            // The next search gets the engine without waiting for the infinite one.
            let mate = try await engine.evaluate(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", depth: 6)
            #expect(mate.mate == 1)
            #expect(clock.now - stopped < .seconds(2))
            #expect(try await reader.value > 0)
        }

        @Test func aStreamEndedBeforeItStartsNeverSearches() async throws {
            let engine = try await startedEngine()
            // Several positions in a row, as when a player steps through moves:
            // only the last one matters, and each earlier one gives way.
            for fen in [Position.italian, "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"] {
                let reader = Task { for try await _ in engine.liveSearch(fen: fen) {} }
                reader.cancel()
                _ = try? await reader.value
            }
            var mates: [Int?] = []
            for try await update in engine.liveSearch(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", lines: 1, maxDepth: 4) {
                mates.append(update.lines.first?.mate)
            }
            #expect(mates.last == 1)
        }

        @Test func stopSearchEndsAOneShotSearchEarly() async throws {
            let engine = try await startedEngine()
            let clock = ContinuousClock()
            let started = clock.now
            async let long = engine.evaluate(fen: Position.italian, depth: 60, maxTime: .seconds(20))
            try await Task.sleep(for: .milliseconds(400))
            await engine.stopSearch()
            let result = try await long
            #expect(result.depth > 0)
            #expect(clock.now - started < .seconds(5))
        }
    }
}

private enum Position {
    static let italian = "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
}
