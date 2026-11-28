import ChessCore
import Foundation

// The player's own opening repertoires (`/api/v1/repertoires*`). A move is
// named by its path: the moves from the start of the repertoire, in UCI.
// Node ids are not part of the contract.

nonisolated struct RepertoireCard: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// "WHITE" or "BLACK": the side the repertoire is for.
    let color: String
    /// The training deck, as `POST /training/grades` and `DueSummary` name it.
    let deck: String
    let lines: Int
    let moves: Int
    let progress: DeckProgress
    /// False for the repertoires the free plan keeps for reading only.
    let editable: Bool
    let updatedAt: Date

    var side: Side { color == "BLACK" ? .black : .white }
}

nonisolated struct RepertoireList: Codable, Hashable, Sendable {
    let repertoires: [RepertoireCard]
    /// Distinct due moves across the repertoires.
    let totalDue: Int
    /// The repertoire to train first, when there is one.
    let top: String?
    let canCreate: Bool
}

/// One move of the tree, with what follows it. The first child is the main
/// continuation; the others are alternatives.
nonisolated struct RepertoireNode: Codable, Hashable, Sendable {
    let san: String
    let uci: String
    /// The position after the move.
    let fen: String
    let ply: Int
    let comments: [String]
    let nags: [Int]
    let shapes: [LineStep.Shape]
    let children: [RepertoireNode]
}

nonisolated struct RepertoireDetail: Codable, Hashable, Identifiable, Sendable {
    struct Pace: Codable, Hashable, Sendable {
        let perDay: Int
        let newLeft: Int
    }

    let id: String
    let name: String
    let color: String
    let deck: String
    let lines: Int
    let moves: Int
    let progress: DeckProgress
    let editable: Bool
    let updatedAt: Date
    let startFen: String
    /// Never nested deeper than 200 moves: see `truncated`.
    var tree: [RepertoireNode]
    /// True when a line was longer than the 200 moves `tree` holds. Nothing
    /// is lost: `pgn` always has the whole line, and edits apply to it.
    let truncated: Bool
    /// The note before the first move.
    let rootComment: String
    let pgn: String
    /// The free plan's line allowance; nil with Premium.
    let lineLimit: Int?
    let pace: Pace

    var side: Side { color == "BLACK" ? .black : .white }
}

/// What is played from one position, and what the repertoire lacks there.
nonisolated struct RepertoirePosition: Codable, Hashable, Sendable {
    struct Move: Codable, Hashable, Sendable {
        let san: String
        let uci: String
        let games: Int
        /// Results by colour: games won by White, drawn, won by Black.
        let white: Int
        let draws: Int
        let black: Int
        /// Share of the games of the position, 0…1.
        let freq: Double
        let whiteScore: Double
        let opening: String?
    }

    /// A reference database at this position.
    struct Database: Codable, Hashable, Sendable {
        let total: Int
        let moves: [Move]
    }

    struct RatingBand: Codable, Hashable, Sendable {
        let ratings: String
        let label: String
    }

    /// The player's own games from this position, with the repertoire's colour.
    struct Mine: Codable, Hashable, Sendable {
        let san: String
        let uci: String?
        let games: Int
        let freq: Double
        let score: Double
        let wins: Int
        let draws: Int
        let losses: Int
    }

    /// A frequent reply of the opponent the repertoire has no answer to.
    struct Gap: Codable, Hashable, Sendable {
        let san: String
        let uci: String
        let freq: Double
        let opening: String?
    }

    /// Whether the line is worth extending: "keep", "consider" or "stop".
    struct Advice: Codable, Hashable, Sendable {
        let kind: String
        let title: String
        let detail: String
        let moveNumber: Int
    }

    let fen: String
    /// The moves to the position, in the spelling of the tree (see
    /// `CastlingSpelling`), not as the request wrote them.
    var path: [String]
    let san: [String]
    let inRepertoire: Bool
    /// The moves the repertoire holds from here, in UCI.
    var covered: [String]
    /// Nil when the reference explorer could not be reached.
    var masters: Database?
    var lichess: Database?
    /// The rating band the Lichess numbers are for.
    let ratings: String
    let ratingBands: [RatingBand]
    var mine: [Mine]
    let opponentToMove: Bool
    var gaps: [Gap]
    let advice: Advice
}

/// The player's latest games checked against a repertoire.
nonisolated struct RepertoireAdherence: Codable, Hashable, Sendable {
    struct Deviation: Codable, Hashable, Sendable {
        let ply: Int
        let moveNumber: Int
        /// What the repertoire holds there, in SAN.
        let expected: [String]
        let played: String
    }

    struct Game: Codable, Hashable, Identifiable, Sendable {
        let gameId: String
        let opponent: String
        /// "win", "draw", "loss" from the player's side; nil when unknown.
        let result: String?
        let playedAt: Date
        let url: String?
        /// "followed", "deviated", "out_of_book" or "no_overlap".
        let status: String
        let pliesFollowed: Int
        let deviation: Deviation?

        var id: String { gameId }
    }

    let hasTree: Bool
    let followed: Int
    let deviated: Int
    let games: [Game]
}

nonisolated struct RepertoireImport: Codable, Hashable, Sendable {
    let repertoire: RepertoireDetail
    /// Games of the PGN merged into the tree, and those left out because they
    /// start from another position.
    let merged: Int
    let skipped: Int
}

nonisolated struct RepertoireSeed: Codable, Hashable, Sendable {
    let repertoire: RepertoireDetail
    /// The player's games the tree was built from.
    let games: Int
}

// MARK: Requests

nonisolated struct CreateRepertoireRequest: Codable, Sendable {
    let name: String
    let color: String
}

nonisolated struct RenameRepertoireRequest: Codable, Sendable {
    let name: String
}

nonisolated struct RepertoireLineRequest: Codable, Sendable {
    /// The moves from the start position, in UCI.
    let line: [String]
}

nonisolated struct ImportRepertoirePgnRequest: Codable, Sendable {
    let pgn: String
}

/// The glyph of a move: left as it is, removed, or set to a NAG (1…6).
nonisolated enum GlyphChange: Hashable, Sendable {
    case keep, clear, set(Int)
}

/// The note and the glyph of a move; an empty path is the note before the
/// first move. A field left out is kept; `null` clears it.
nonisolated struct AnnotateRepertoireMoveRequest: Encodable, Sendable {
    let path: [String]
    /// Nil keeps the note; an empty text removes it.
    var comment: String?
    var glyph: GlyphChange = .keep

    private enum CodingKeys: String, CodingKey { case path, comment, nag }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        if let comment { try container.encode(comment, forKey: .comment) }
        switch glyph {
        case .keep: break
        case .clear: try container.encodeNil(forKey: .nag)
        case let .set(nag): try container.encode(nag, forKey: .nag)
        }
    }
}
