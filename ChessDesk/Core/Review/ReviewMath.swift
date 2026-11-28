import Foundation

// The arithmetic of a game review, ported from the site
// (`apps/web/lib/review/win-chance.ts` and `classify.ts`) so a game reviewed
// on the phone reads the same as one reviewed in the browser. The formulas
// are Lichess's published ones; the thresholds are ChessDesk's.

nonisolated enum MoveClass: String, Codable, Hashable, Sendable, CaseIterable {
    case brilliant = "BRILLIANT", great = "GREAT", best = "BEST", good = "GOOD"
    case inaccuracy = "INACCURACY", mistake = "MISTAKE", blunder = "BLUNDER", book = "BOOK"

    var label: String {
        switch self {
        case .brilliant: "Brilliant"
        case .great: "Great"
        case .best: "Best"
        case .good: "Good"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        case .blunder: "Blunder"
        case .book: "Book"
        }
    }

    var isError: Bool { self == .mistake || self == .blunder }
}

nonisolated enum ReviewMath {
    static let centipawnCeiling = 1000.0
    /// Lichess's fixed evaluation of the starting position.
    static let initialCentipawns = 15.0

    static let inaccuracy = 5.0
    static let mistake = 10.0
    static let blunder = 20.0
    static let greatTopTolerance = 2.0
    static let greatOnlyMoveGap = 18.0
    static let brilliantSacrificeMaterial = 2
    static let brilliantSoundWin = 45.0

    /// Centipawns (side to move) to a win percentage, 0 to 100.
    static func winPercent(centipawns: Double) -> Double {
        let clamped = max(-centipawnCeiling, min(centipawnCeiling, centipawns))
        let chances = 2 / (1 + exp(-0.00368208 * clamped)) - 1
        return 50 + 50 * max(-1, min(1, chances))
    }

    /// A mate is the centipawn ceiling through the same curve, not a hard 100.
    /// Mate 0 is the side to move already checkmated.
    static func winPercent(centipawns: Double?, mate: Int?) -> Double {
        if let mate {
            if mate == 0 { return 0 }
            return winPercent(centipawns: mate > 0 ? centipawnCeiling : -centipawnCeiling)
        }
        guard let centipawns else { return 50 }
        return winPercent(centipawns: centipawns)
    }

    struct Judgement {
        var winBefore: Double
        var winAfter: Double
        var isTopMove: Bool
        var ply: Int
        var evalCentipawns: Double?
        /// Win percentage of the runner-up line, for the mover; nil without one.
        var secondBestWin: Double?
        /// Points of material the mover is down once the line settles (negative: a sacrifice).
        var materialDelta: Int?
    }

    static func classify(_ move: Judgement) -> MoveClass {
        let loss = max(0, move.winBefore - move.winAfter)
        if loss >= blunder { return .blunder }
        if loss >= mistake { return .mistake }
        if loss >= inaccuracy { return .inaccuracy }

        if move.isTopMove || loss <= greatTopTolerance {
            if let delta = move.materialDelta, delta <= -brilliantSacrificeMaterial, move.winAfter >= brilliantSoundWin {
                return .brilliant
            }
            if let second = move.secondBestWin, move.winBefore - second >= greatOnlyMoveGap {
                return .great
            }
        }
        if move.ply < 10, loss < 2, let cp = move.evalCentipawns, abs(cp) < 50 { return .book }
        if move.isTopMove || loss < 1 { return .best }
        return .good
    }

    /// Lichess's accuracy of one move from the win percentage it lost.
    static func moveAccuracy(winBefore: Double, winAfter: Double) -> Double {
        if winAfter >= winBefore { return 100 }
        let raw = 103.1668100711649 * exp(-0.04354415386753951 * (winBefore - winAfter)) - 3.166924740191411
        return max(0, min(100, raw + 1))
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
    }

    /// Each term floored at 1, so one blunder weighs on the whole game.
    static func harmonicMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.count) / values.reduce(0) { $0 + 1 / max(1, $1) }
    }

    /// One weight per move from the win percentages of every position,
    /// White's view, the starting position included (count = moves + 1).
    static func volatilityWeights(_ winPercents: [Double]) -> [Double] {
        let count = winPercents.count
        guard count >= 2 else { return [] }
        let window = max(2, min(8, (count - 1) / 10))
        var windows: [[Double]] = []
        let padding = min(window, count) - 2
        let first = Array(winPercents.prefix(window))
        for _ in 0..<max(0, padding) { windows.append(first) }
        var start = 0
        while start + window <= count {
            windows.append(Array(winPercents[start..<(start + window)]))
            start += 1
        }
        return windows.map { max(0.5, min(12, standardDeviation($0))) }
    }

    /// The mean of a volatility-weighted mean and a harmonic mean, one decimal.
    static func blendedAccuracy(_ accuracies: [Double], weights: [Double]) -> Double {
        guard !accuracies.isEmpty else { return 0 }
        var weighted = 0.0, total = 0.0
        for (index, accuracy) in accuracies.enumerated() {
            let weight = index < weights.count ? weights[index] : 1
            weighted += accuracy * weight
            total += weight
        }
        let mean = total > 0 ? weighted / total : 0
        let blended = (mean + harmonicMean(accuracies)) / 2
        return (max(0, min(100, blended)) * 10).rounded() / 10
    }
}
