import ChessCore
import Foundation

/// Castling has two UCI spellings. The server's opening trees write it as the
/// king taking its own rook (`e1h1`, `e1a1`, `e8h8`, `e8a8`), in every `uci`
/// of an answer about a tree and in `RepertoirePosition.path`. ChessCore and
/// the board write the king's own move (`e1g1`, `e1c1`, `e8g8`, `e8c8`).
/// Requests may use either.
///
/// Inside the app a move of a tree is always in the board's spelling: the
/// screens respell an answer when it arrives (`boardSpelled`), so that a move
/// played on the board, a path and a node of the tree compare as text.
nonisolated enum CastlingSpelling {
    private static let boardFromTree = ["e1h1": "e1g1", "e1a1": "e1c1", "e8h8": "e8g8", "e8a8": "e8c8"]
    private static let treeFromBoard = ["e1g1": "e1h1", "e1c1": "e1a1", "e8g8": "e8h8", "e8c8": "e8a8"]

    /// A move whose SAN is known, in the board's spelling.
    static func board(_ uci: String, san: String) -> String {
        san.hasPrefix("O-O") ? boardFromTree[uci] ?? uci : uci
    }

    /// A move played from `position`, in the board's spelling.
    static func board(_ uci: String, from position: Position) -> String {
        guard boardFromTree[uci] != nil, let move = Move(uci: uci) else { return uci }
        return position.normalized(move).uci
    }

    /// A path played from `startFen`, in the board's spelling. A move the
    /// rules refuse and what follows it are left as written.
    static func board(path: [String], from startFen: String) -> [String] {
        guard path.contains(where: { boardFromTree[$0] != nil }), var position = Position(fen: startFen) else { return path }
        var spelled: [String] = []
        for (index, uci) in path.enumerated() {
            guard let move = Move(uci: uci), let next = position.playing(move) else {
                return spelled + path[index...]
            }
            spelled.append(position.normalized(move).uci)
            position = next
        }
        return spelled
    }

    /// A move whose SAN is known, as the server's trees spell it. The sample
    /// data answers this way, as production does.
    static func tree(_ uci: String, san: String) -> String {
        san.hasPrefix("O-O") ? treeFromBoard[uci] ?? uci : uci
    }

    /// A move played from `position`, as the server's trees spell it.
    static func tree(_ uci: String, from position: Position) -> String {
        guard let move = Move(uci: uci) else { return uci }
        let played = position.normalized(move)
        return position.isCastling(played) ? treeFromBoard[played.uci] ?? played.uci : played.uci
    }
}

// MARK: Answers respelled for the app

nonisolated extension RepertoireNode {
    /// The move and everything below it with castling spelled `spell(uci, san)`.
    func respelled(_ spell: (String, String) -> String) -> RepertoireNode {
        RepertoireNode(
            san: san, uci: spell(uci, san), fen: fen, ply: ply, comments: comments, nags: nags, shapes: shapes,
            children: children.map { $0.respelled(spell) }
        )
    }
}

nonisolated extension RepertoireDetail {
    /// The repertoire with the castling moves of its tree in the board's spelling.
    var boardSpelled: RepertoireDetail { respelled(CastlingSpelling.board(_:san:)) }
    /// The repertoire as the server writes it: what the sample data answers.
    var treeSpelled: RepertoireDetail { respelled(CastlingSpelling.tree(_:san:)) }

    private func respelled(_ spell: (String, String) -> String) -> RepertoireDetail {
        var copy = self
        copy.tree = tree.map { $0.respelled(spell) }
        return copy
    }
}

nonisolated extension RepertoirePosition {
    /// The position with every move in the board's spelling: its path, the
    /// moves the repertoire holds, and the moves played from it.
    var boardSpelled: RepertoirePosition {
        respelled(CastlingSpelling.board(_:san:), CastlingSpelling.board(_:from:))
    }

    /// The position as the server writes it: what the sample data answers.
    var treeSpelled: RepertoirePosition {
        respelled(CastlingSpelling.tree(_:san:), CastlingSpelling.tree(_:from:))
    }

    private func respelled(
        _ spell: (String, String) -> String, _ spellHere: (String, Position) -> String
    ) -> RepertoirePosition {
        let here = Position(fen: fen)
        var copy = self
        // `san` names the same moves as `path`.
        copy.path = zip(path, san).map { spell($0, $1) } + path.dropFirst(san.count)
        copy.covered = covered.map { uci in here.map { spellHere(uci, $0) } ?? uci }
        copy.masters = masters.map { .init(total: $0.total, moves: $0.moves.map { $0.respelled(spell) }) }
        copy.lichess = lichess.map { .init(total: $0.total, moves: $0.moves.map { $0.respelled(spell) }) }
        copy.mine = mine.map { $0.respelled(spell) }
        copy.gaps = gaps.map { $0.respelled(spell) }
        return copy
    }
}

nonisolated extension RepertoirePosition.Move {
    func respelled(_ spell: (String, String) -> String) -> RepertoirePosition.Move {
        .init(
            san: san, uci: spell(uci, san), games: games, white: white, draws: draws, black: black, freq: freq,
            whiteScore: whiteScore, opening: opening
        )
    }
}

nonisolated extension RepertoirePosition.Mine {
    func respelled(_ spell: (String, String) -> String) -> RepertoirePosition.Mine {
        .init(
            san: san, uci: uci.map { spell($0, san) }, games: games, freq: freq, score: score, wins: wins, draws: draws,
            losses: losses
        )
    }
}

nonisolated extension RepertoirePosition.Gap {
    func respelled(_ spell: (String, String) -> String) -> RepertoirePosition.Gap {
        .init(san: san, uci: spell(uci, san), freq: freq, opening: opening)
    }
}
