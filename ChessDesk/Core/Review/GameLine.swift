import ChessCore
import Foundation

/// The moves of a game as played, read from its PGN: what the board replays
/// and what the engine reviews. Comments, variations and annotation glyphs
/// are dropped; a move the rules refuse ends the line there.
nonisolated struct GameLine: Hashable, Sendable {
    struct Played: Hashable, Sendable {
        let san: String
        let move: Move
        let fenAfter: String
        /// 1 for White's first move.
        let ply: Int
        let side: Side
    }

    let startFEN: String
    let moves: [Played]
    let headers: [String: String]

    /// The FEN of every position, the start included: `moves.count + 1` of them.
    var fens: [String] { [startFEN] + moves.map(\.fenAfter) }

    func fen(atPly ply: Int) -> String {
        ply <= 0 ? startFEN : moves[min(ply, moves.count) - 1].fenAfter
    }

    init(pgn: String) {
        var headers: [String: String] = [:]
        var body = ""
        for raw in pgn.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                let inner = line.dropFirst().dropLast()
                if let space = inner.firstIndex(of: " ") {
                    let value = inner[inner.index(after: space)...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                    headers[String(inner[..<space])] = value
                }
            } else {
                body += line + " "
            }
        }
        self.headers = headers
        let start = headers["FEN"].flatMap { Position(fen: $0) } ?? .start
        startFEN = start.fen

        var position = start
        var played: [Played] = []
        let firstPly = (start.fullmoveNumber - 1) * 2 + (start.turn == .white ? 1 : 2)
        for token in Self.tokens(body) {
            guard let move = position.move(san: token), let san = position.san(for: move),
                  let next = position.playing(move)
            else { break }
            played.append(Played(san: san, move: move, fenAfter: next.fen, ply: firstPly + played.count, side: position.turn))
            position = next
        }
        moves = played
    }

    /// Movetext to SAN tokens: no comments, variations, glyphs, numbers or result.
    static func tokens(_ movetext: String) -> [String] {
        var text = ""
        var depth = 0
        var inComment = false
        for character in movetext {
            if inComment {
                if character == "}" { inComment = false }
                continue
            }
            switch character {
            case "{": inComment = true
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            default: if depth == 0 { text.append(character) }
            }
        }
        let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]
        return text.split(whereSeparator: \.isWhitespace).compactMap { raw in
            var token = String(raw)
            if results.contains(token) || token.hasPrefix("$") { return nil }
            // "12." and "12..." may be glued to the move: "12.e4".
            if let dot = token.lastIndex(of: "."), token[..<dot].allSatisfy({ $0.isNumber || $0 == "." }) {
                token = String(token[token.index(after: dot)...])
            }
            guard let first = token.first, first.isLetter || token.hasPrefix("0-0") else { return nil }
            return token
        }
    }
}
