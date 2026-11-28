import ChessCore
import Foundation

/// A named opening: "B90 Sicilian Defense: Najdorf Variation".
nonisolated struct Opening: Hashable, Sendable {
    let eco: String
    let name: String
    /// The line that names it, in SAN: "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6".
    let moves: String
}

/// The names of the openings, from the site's reference
/// (`apps/web/lib/openings/eco-openings.json`, the Lichess chess-openings
/// list, public domain), matched as the site's opening name finder does
/// (`apps/web/components/opening-name-finder/identify.ts`): by position
/// first, so a transposition finds its name, the moves played breaking a
/// tie; then by the longest named start of the line.
nonisolated final class OpeningBook: Sendable {
    private let rows: [Opening]
    /// Position (pieces, side to move, castling) to the openings that reach
    /// it, shortest line first, then by name.
    private let byPosition: [String: [Opening]]

    init(rows: [Opening]) {
        self.rows = rows
        var index: [String: [Opening]] = [:]
        // Lines sorted move by move share their starts: each prefix is
        // played once.
        let sorted = rows.map { (opening: $0, tokens: $0.moves.split(separator: " ").map(String.init)) }
            .sorted { $0.tokens.lexicographicallyPrecedes($1.tokens) }
        var previous: [String] = []
        var positions: [Position] = [.start]
        for (opening, tokens) in sorted {
            let shared = zip(previous, tokens).prefix { $0 == $1 }.count
            positions.removeLast(positions.count - 1 - shared)
            var failed = false
            for token in tokens.dropFirst(shared) {
                guard let last = positions.last, let move = last.move(san: token), let next = last.playing(move) else {
                    failed = true
                    break
                }
                positions.append(next)
            }
            // A bad source row must not make the whole book unavailable.
            if failed {
                previous = Array(tokens.prefix(positions.count - 1))
                continue
            }
            previous = tokens
            if let last = positions.last {
                index[Self.key(last), default: []].append(opening)
            }
        }
        for key in index.keys {
            index[key]?.sort {
                let lhs = $0.moves.split(separator: " ").count
                let rhs = $1.moves.split(separator: " ").count
                return lhs != rhs ? lhs < rhs : $0.name < $1.name
            }
        }
        byPosition = index
    }

    /// The book bundled with the app, read and indexed off the main thread
    /// the first time it is asked for.
    static func bundled() async -> OpeningBook? {
        await Loader.shared.book()
    }

    /// The opening of a game that reached `position` by `moves` (SAN, from
    /// the standard start). Nil when the line has no name.
    func identify(moves: [String], position: Position) -> Opening? {
        positionMatch(moves: moves, position: position) ?? longestStart(of: moves)
    }

    /// The opening whose position this is, preferring the one named by
    /// exactly these moves.
    func positionMatch(moves: [String], position: Position) -> Opening? {
        guard let candidates = byPosition[Self.key(position)], !candidates.isEmpty else { return nil }
        let entered = moves.map(Self.bare).joined(separator: " ")
        return candidates.first { Self.bareLine($0.moves) == entered } ?? candidates[0]
    }

    /// The longest named line these moves start with.
    func longestStart(of moves: [String]) -> Opening? {
        let entered = moves.map(Self.bare).joined(separator: " ")
        var best: Opening?
        var bestLength = 0
        for row in rows {
            let line = Self.bareLine(row.moves)
            guard entered == line || entered.hasPrefix(line + " ") else { continue }
            let length = row.moves.split(separator: " ").count
            if length > bestLength {
                best = row
                bestLength = length
            }
        }
        return best
    }

    /// The opening of a position alone, as when a FEN is pasted.
    func identify(position: Position) -> Opening? {
        byPosition[Self.key(position)]?.first
    }

    /// Opening identity follows the position, not the move counters or the
    /// en passant square (the site's `positionKey`).
    static func key(_ position: Position) -> String {
        position.fen.split(separator: " ").prefix(3).joined(separator: " ")
    }

    private static func bare(_ san: String) -> String {
        san.filter { !"+#!?".contains($0) }
    }

    private static func bareLine(_ moves: String) -> String {
        moves.split(separator: " ").map { bare(String($0)) }.joined(separator: " ")
    }

    private actor Loader {
        static let shared = Loader()
        private var loading: Task<OpeningBook?, Never>?

        func book() async -> OpeningBook? {
            if let loading { return await loading.value }
            let task = Task.detached(priority: .utility) { () -> OpeningBook? in
                guard let url = Bundle.main.url(forResource: "eco-openings", withExtension: "json"),
                      let data = try? Data(contentsOf: url)
                else { return nil }
                return OpeningBook(json: data)
            }
            loading = task
            return await task.value
        }
    }
}

nonisolated extension OpeningBook {
    private struct Row: Decodable {
        let eco: String
        let name: String
        let moves: String
    }

    /// Reads the site's JSON: `[{"eco": "A00", "name": "…", "moves": "Nh3"}]`.
    convenience init?(json: Data) {
        guard let rows = try? JSONDecoder().decode([Row].self, from: json) else { return nil }
        self.init(rows: rows.map { Opening(eco: $0.eco, name: $0.name, moves: $0.moves) })
    }
}
