import ChessCore
import Foundation

// The opening explorer of the player's own games (`/api/v1/explorer*`). A
// position is named by the moves in SAN, exactly as `moves[].san` gives them.

nonisolated struct ExplorerSummary: Codable, Hashable, Sendable {
    /// Games that can be explored, per colour.
    let white: Int
    let black: Int
    let imported: Int
    /// The free plan explores the most recent games, up to this many; nil with Premium.
    let limit: Int?
    /// True when the player has more games than the free plan explores.
    let capped: Bool
    let hasLinkedAccount: Bool

    var isEmpty: Bool { white + black == 0 }
}

nonisolated struct ExplorerPosition: Codable, Hashable, Sendable {
    struct Move: Codable, Hashable, Sendable {
        let san: String
        let uci: String?
        let games: Int
        /// From the player's side.
        let wins: Int
        let draws: Int
        let losses: Int
        /// (wins + draws / 2) / games, 0…1.
        let score: Double
        let sampleGameId: String
    }

    /// A line worth opening first.
    struct Insight: Codable, Hashable, Sendable {
        let path: [String]
        /// "1.e4 e5 2.Nf3"
        let line: String
        let games: Int
        let score: Double
    }

    struct Insights: Codable, Hashable, Sendable {
        let mostPlayed: Insight?
        let best: Insight?
        let leak: Insight?
    }

    let side: String
    let path: [String]
    let fen: String
    /// Games of the chosen colour matching the filters.
    let total: Int
    /// Games that reached this position.
    let reaching: Int
    let activeFilters: Int
    let limit: Int?
    let moves: [Move]
    /// The stored opening moves end here.
    let endOfData: Bool
    /// The newest games that reached the position.
    let games: [GameSummary]
    let insights: Insights
}

/// What the explorer narrows the games by, as the site's filter panel does
/// (`components/explorer/explorer-filters.tsx`).
nonisolated struct ExplorerFilters: Hashable, Sendable {
    enum Rated: String, Hashable, Sendable, CaseIterable {
        case all, rated, casual
    }

    static let timeClasses = ["BULLET", "BLITZ", "RAPID", "CLASSICAL", "CORRESPONDENCE"]

    var side: Side = .white
    var timeClasses: Set<String> = []
    var rated: Rated = .all
    /// Days, "yyyy-MM-dd".
    var dateFrom: String?
    var dateTo: String?
    var opponentMin: Int?
    var opponentMax: Int?
    /// One game site only; nil is both.
    var source: GameProvider?

    /// How many optional filters narrow the view, the side apart. Same count
    /// as the site's `lib/explorer/filter-count.ts`.
    var activeCount: Int {
        var count = 0
        if !timeClasses.isEmpty { count += 1 }
        if rated != .all { count += 1 }
        if dateFrom != nil || dateTo != nil { count += 1 }
        if opponentMin != nil || opponentMax != nil { count += 1 }
        if source != nil { count += 1 }
        return count
    }

    /// The same view with every optional filter removed.
    var cleared: ExplorerFilters { ExplorerFilters(side: side) }

    /// The day of a date on the player's calendar, as the API reads it.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
