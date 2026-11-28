import Foundation

/// Elo arithmetic, ported from the site (`apps/web/lib/elo/elo.ts` and
/// `lib/elo/performance.ts`) with its tests' numbers.
nonisolated enum EloMath {
    /// Expected score of `player` against `opponent`: 1 / (1 + 10^((Ro − Rp) / 400)).
    static func expectedScore(player: Double, opponent: Double) -> Double {
        1 / (1 + pow(10, (opponent - player) / 400))
    }

    /// FIDE's 400-point rule (Rating Regulations 2024, art. 8.3.1): below
    /// 2650, a gap of more than 400 points counts as 400.
    static let maxCountedDifference: Double = 400
    static let fullDifferenceFrom: Double = 2650

    static func countedOpponent(player: Double, opponent: Double) -> Double {
        guard player < fullDifferenceFrom else { return opponent }
        let gap = opponent - player
        if gap > maxCountedDifference { return player + maxCountedDifference }
        if gap < -maxCountedDifference { return player - maxCountedDifference }
        return opponent
    }

    /// K × (S − E), not rounded.
    static func ratingChange(player: Double, opponent: Double, score: Double, k: Double) -> Double {
        k * (score - expectedScore(player: player, opponent: opponent))
    }

    /// FIDE's table of rating differences by score percentage, 0 to 100.
    static let dpTable: [Int] = [
        -800, -677, -589, -538, -501, -470, -444, -422, -401, -383,
        -366, -351, -336, -322, -309, -296, -284, -273, -262, -251,
        -240, -230, -220, -211, -202, -193, -184, -175, -166, -158,
        -149, -141, -133, -125, -117, -110, -102, -95, -87, -80,
        -72, -65, -57, -50, -43, -36, -29, -21, -14, -7,
        0, 7, 14, 21, 29, 36, 43, 50, 57, 65,
        72, 80, 87, 95, 102, 110, 117, 125, 133, 141,
        149, 158, 166, 175, 184, 193, 202, 211, 220, 230,
        240, 251, 262, 273, 284, 296, 309, 322, 336, 351,
        366, 383, 401, 422, 444, 470, 501, 538, 589, 677,
        800,
    ]

    /// The table's value for a percentage, rounded half away from zero (as
    /// JavaScript rounds the positive percentages) and clamped to 0…100.
    static func dp(scorePercent: Double) -> Int {
        dpTable[min(100, max(0, Int((scorePercent).rounded(.toNearestOrAwayFromZero))))]
    }

    struct Game: Hashable {
        let opponent: Double
        /// 1 a win, 0.5 a draw, 0 a loss.
        let score: Double
    }

    /// Average opponent (rounded) plus dp of the score percentage; nil without games.
    static func performance(_ games: [Game]) -> Int? {
        guard !games.isEmpty else { return nil }
        let average = games.reduce(0) { $0 + $1.opponent } / Double(games.count)
        let percent = games.reduce(0) { $0 + $1.score } / Double(games.count) * 100
        return Int(average.rounded(.toNearestOrAwayFromZero)) + dp(scorePercent: percent)
    }

    /// Reads a rating field: nil when empty or not a number, so the screen
    /// shows a dash instead of nonsense.
    static func rating(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}

/// The two results of the rating change tab, formatted as the site prints them.
nonisolated struct RatingChangeResult: Equatable {
    let expected: String
    let delta: String
    let newRating: String
    /// The gap was over 400 and counted as 400.
    let capped: Bool

    init?(player: Double?, opponent: Double?, score: Double, k: Double) {
        guard let player, let opponent else { return nil }
        let counted = EloMath.countedOpponent(player: player, opponent: opponent)
        let expected = EloMath.expectedScore(player: player, opponent: counted)
        let delta = EloMath.ratingChange(player: player, opponent: counted, score: score, k: k)
        let english = Locale(identifier: "en_US")
        self.expected = expected.formatted(.number.precision(.fractionLength(3)).rounded(rule: .toNearestOrAwayFromZero).locale(english))
        let deltaText = delta.formatted(.number.precision(.fractionLength(1)).rounded(rule: .toNearestOrAwayFromZero).locale(english))
        self.delta = delta >= 0 ? "+\(deltaText)" : deltaText
        newRating = String(Int((player + delta).rounded(.toNearestOrAwayFromZero)))
        capped = counted != opponent
    }
}
