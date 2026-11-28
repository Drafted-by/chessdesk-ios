import ChessCore
import Foundation
import StockfishEngine

/// What the engine said of one position, from the side to move.
nonisolated struct PositionEval: Hashable, Sendable {
    var centipawns: Double?
    var mate: Int?
    var bestSAN = ""
    var bestUCI = ""
    /// The runner-up line, same point of view; nil when there is none.
    var secondCentipawns: Double?
    var secondMate: Int?

    static let unknown = PositionEval()
}

/// Turns the engine's evaluations of every position of a game into its
/// review. A port of the site's `lib/review/build-review.ts`; one difference:
/// a sacrifice is detected from the material once the line settles only (the
/// site also reads a static exchange on the destination square), so the app
/// awards Brilliant a little less often.
nonisolated enum ReviewBuilder {
    /// `evals` holds one evaluation per position: `line.moves.count + 1`.
    static func build(line: GameLine, evals: [PositionEval], depth: Int, now: Date = .now) -> GameReview {
        let fens = line.fens
        let evals = zip(fens, evals).map { fen, eval in terminal(fen) ?? eval }
        let count = line.moves.count
        guard count > 0, evals.count == count + 1 else {
            return GameReview(version: 1, depth: depth, computedAt: now, whiteAccuracy: 0, blackAccuracy: 0, moves: [])
        }

        // Win percentage from White's side at every position.
        var whiteWin: [Double] = []
        for index in 0...count {
            let whiteToMove = index < count ? line.moves[index].side == .white : line.moves[count - 1].side == .black
            if index == 0, line.startFEN == Position.startFEN {
                whiteWin.append(ReviewMath.winPercent(centipawns: ReviewMath.initialCentipawns))
                continue
            }
            let win = ReviewMath.winPercent(centipawns: evals[index].centipawns, mate: evals[index].mate)
            whiteWin.append(whiteToMove ? win : 100 - win)
        }
        let weights = ReviewMath.volatilityWeights(whiteWin)

        var moves: [ReviewedMove] = []
        var accuracy: [Side: [Double]] = [.white: [], .black: []]
        var weight: [Side: [Double]] = [.white: [], .black: []]
        for (index, played) in line.moves.enumerated() {
            let before = evals[index]
            let after = evals[index + 1]
            let white = played.side == .white
            let winBefore = white ? whiteWin[index] : 100 - whiteWin[index]
            let winAfter = white ? whiteWin[index + 1] : 100 - whiteWin[index + 1]
            let moverAfterCp = after.centipawns.map { -$0 }
            let moverAfterMate = after.mate.map { $0 == 0 ? 0 : -$0 }

            var secondBestWin: Double?
            if before.secondCentipawns != nil || before.secondMate != nil {
                secondBestWin = ReviewMath.winPercent(centipawns: before.secondCentipawns, mate: before.secondMate)
            }
            let settled = index + 1 < count ? line.moves[index + 1].fenAfter : played.fenAfter
            let delta = material(fen: settled, for: played.side) - material(fen: fens[index], for: played.side)

            let classification = ReviewMath.classify(.init(
                winBefore: winBefore,
                winAfter: winAfter,
                isTopMove: before.bestSAN == played.san,
                ply: played.ply,
                evalCentipawns: before.centipawns,
                secondBestWin: secondBestWin,
                materialDelta: delta
            ))
            accuracy[played.side]?.append(ReviewMath.moveAccuracy(winBefore: winBefore, winAfter: winAfter))
            weight[played.side]?.append(index < weights.count ? weights[index] : 1)

            var loss = 0.0
            if let beforeCp = before.centipawns, let afterCp = moverAfterCp { loss = max(0, beforeCp - afterCp) }
            moves.append(ReviewedMove(
                ply: played.ply,
                san: played.san,
                color: white ? "w" : "b",
                evalCp: white ? moverAfterCp : after.centipawns,
                mate: white ? moverAfterMate : after.mate,
                bestSan: before.bestSAN,
                cpl: loss,
                winLoss: max(0, winBefore - winAfter),
                classification: classification
            ))
        }
        return GameReview(
            version: 1,
            depth: depth,
            computedAt: now,
            whiteAccuracy: ReviewMath.blendedAccuracy(accuracy[.white] ?? [], weights: weight[.white] ?? []),
            blackAccuracy: ReviewMath.blendedAccuracy(accuracy[.black] ?? [], weights: weight[.black] ?? [])
        , moves: moves)
    }

    /// A finished position is decided by the rules, not the engine: checkmate
    /// is mate 0 for the side to move, a dead draw is 0.
    static func terminal(_ fen: String) -> PositionEval? {
        guard let position = Position(fen: fen), let outcome = position.outcome else { return nil }
        switch outcome {
        case .checkmate: return PositionEval(centipawns: nil, mate: 0)
        case .stalemate, .insufficientMaterial: return PositionEval(centipawns: 0, mate: nil)
        case .fiftyMoveRule: return nil
        }
    }

    /// Material of `side` minus the opponent's, in points (kings not counted).
    static func material(fen: String, for side: Side) -> Int {
        guard let position = Position(fen: fen) else { return 0 }
        var balance = 0
        for piece in position.board.compactMap({ $0 }) {
            let value = switch piece.kind {
            case .pawn: 1
            case .knight, .bishop: 3
            case .rook: 5
            case .queen: 9
            case .king: 0
            }
            balance += piece.side == side ? value : -value
        }
        return balance
    }

    /// The engine's lines for one position, as the review reads them.
    static func eval(lines: [EngineEvaluation], fen: String) -> PositionEval {
        guard let best = lines.first else { return .unknown }
        var eval = PositionEval(centipawns: best.centipawns.map(Double.init), mate: best.mate)
        if let uci = best.bestMove, let position = Position(fen: fen), let move = Move(uci: uci) {
            let legal = position.normalized(move)
            eval.bestUCI = legal.uci
            eval.bestSAN = position.san(for: legal) ?? ""
        }
        if lines.count > 1 {
            eval.secondCentipawns = lines[1].centipawns.map(Double.init)
            eval.secondMate = lines[1].mate
        }
        return eval
    }
}

/// Reviews a game with the engine on the device: every position to the
/// site's depth (18, at most a second and a half each), then the arithmetic.
nonisolated struct GameReviewer: Sendable {
    static let depth = 18
    static let perPosition = Duration.milliseconds(1500)

    /// Evaluates one position; the app's is Stockfish, tests pass a stub.
    var analyse: @Sendable (String) async throws -> PositionEval = GameReviewer.engine()

    /// Stockfish on the device, two lines per position.
    static func engine(
        depth: Int = GameReviewer.depth,
        maxTime: Duration = GameReviewer.perPosition
    ) -> @Sendable (String) async throws -> PositionEval {
        { fen in
            guard let network = DeviceEngine.networkURL else {
                throw EngineError.networkMissing(StockfishEngine.networkName)
            }
            try await StockfishEngine.shared.start(network: network)
            let lines = try await StockfishEngine.shared.analyse(fen: fen, depth: depth, maxTime: maxTime, lines: 2)
            return ReviewBuilder.eval(lines: lines, fen: fen)
        }
    }

    /// `progress` is called with the number of positions done, out of `line.fens.count`.
    func review(_ line: GameLine, progress: @Sendable (Int) async -> Void = { _ in }) async throws -> GameReview {
        var evals: [PositionEval] = []
        for (index, fen) in line.fens.enumerated() {
            try Task.checkCancellation()
            evals.append(ReviewBuilder.terminal(fen) != nil ? .unknown : try await analyse(fen))
            await progress(index + 1)
        }
        return ReviewBuilder.build(line: line, evals: evals, depth: Self.depth)
    }
}
