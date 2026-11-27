import Foundation
import StockfishEngine

/// Something that can evaluate a position: Stockfish in the app, a stub in tests.
nonisolated protocol PositionEvaluating: Sendable {
    func evaluate(fen: String) async throws -> EngineEvaluation
}

/// Stockfish on the device, started the first time it is needed. Its network
/// is a file of the app bundle (`scripts/fetch-nnue.sh`).
nonisolated struct DeviceEngine: PositionEvaluating {
    static var networkURL: URL? {
        let name = StockfishEngine.networkName as NSString
        return Bundle.main.url(forResource: name.deletingPathExtension, withExtension: name.pathExtension)
    }

    func evaluate(fen: String) async throws -> EngineEvaluation {
        guard let network = Self.networkURL else {
            throw EngineError.networkMissing(StockfishEngine.networkName)
        }
        try await StockfishEngine.shared.start(network: network)
        // The site's trainer asks for the same: depth 12, about a second.
        return try await StockfishEngine.shared.evaluate(fen: fen, depth: 12, maxTime: .milliseconds(1200))
    }
}

/// "Is my move as good?" for a position to solve, with the rules of the
/// site's trainer (`apps/web/lib/training/judge.ts`): a move within 35
/// centipawns of the course's move is as good; in an exercise that ends in
/// mate, a move is as good when it still mates on schedule.
nonisolated struct EngineJudge: MoveJudging {
    static let equalLossCentipawns = 35

    var engine: any PositionEvaluating = DeviceEngine()

    func accepts(_ question: JudgeQuestion) async -> Bool {
        do {
            switch question {
            case .accepted:
                return true
            case let .mate(fenAfterPlayed, within):
                // The opponent is to move: "mate -2" says they are mated in two.
                let after = try await engine.evaluate(fen: fenAfterPlayed)
                guard let mate = after.mate, mate < 0 else { return false }
                return -mate <= within
            case let .equal(fenAfterPlayed, fenAfterExpected):
                let played = try await engine.evaluate(fen: fenAfterPlayed)
                let expected = try await engine.evaluate(fen: fenAfterExpected)
                // Both scores are the opponent's: negate for the learner's view.
                let loss = -expected.comparable - -played.comparable
                return loss <= Self.equalLossCentipawns
            }
        } catch {
            // Without the engine, only the course's move counts.
            return false
        }
    }
}
