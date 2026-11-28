/// How the rules end a game. Resignation, time and agreement are decisions
/// of the players and belong to whoever runs the game.
public enum GameEnding: Sendable, Hashable {
    case checkmate(winner: Side)
    case stalemate
    case insufficientMaterial
    case threefoldRepetition
    case fiftyMoveRule

    public var isDraw: Bool {
        if case .checkmate = self { return false }
        return true
    }

    /// The winner; nil for a draw.
    public var winner: Side? {
        if case let .checkmate(winner) = self { return winner }
        return nil
    }
}

/// A draw a player may claim: the game goes on unless somebody does.
public enum DrawClaim: Sendable, Hashable {
    /// The same position, with the same side to move and the same rights,
    /// stands on the board for the third time.
    case threefoldRepetition
    /// Fifty moves by each side without a capture or a pawn move.
    case fiftyMoveRule
}

/// A move as it was played in a game.
public struct PlayedMove: Sendable, Hashable {
    public let move: Move
    public let san: String
    /// The position after the move.
    public let position: Position
    /// Half-move number from the standard start: 1 is White's first move.
    public let ply: Int

    public var side: Side { position.turn.opposite }
    public var moveNumber: Int { (ply + 1) / 2 }
}

/// A game from its first position: the moves played, and what the rules say
/// of the position reached, repetitions included. A value type: `play`
/// refuses anything that is not legal.
public struct Game: Sendable, Hashable {
    public let start: Position
    public private(set) var moves: [PlayedMove] = []
    /// The key of every position that stood on the board, the first included.
    private var keys: [String]

    public init(start: Position = .start) {
        self.start = start
        keys = [start.positionKey]
    }

    /// Replays moves written in UCI; nil when one of them is not legal.
    public init?(start: Position = .start, uciMoves: [String]) {
        self.init(start: start)
        for text in uciMoves {
            guard let move = Move(uci: text), play(move) != nil else { return nil }
        }
    }

    public var position: Position { moves.last?.position ?? start }

    /// Half-moves played before the first position, from its move counter.
    public var startPly: Int {
        (start.fullmoveNumber - 1) * 2 + (start.turn == .black ? 1 : 0)
    }

    // MARK: Playing

    /// Plays a legal move and returns it as played; nil when it is not legal
    /// in the current position (the game is left as it was).
    @discardableResult
    public mutating func play(_ move: Move) -> PlayedMove? {
        let current = position
        let move = current.normalized(move)
        guard let san = current.san(for: move), let next = current.playing(move) else { return nil }
        let played = PlayedMove(move: move, san: san, position: next, ply: startPly + moves.count + 1)
        moves.append(played)
        keys.append(next.positionKey)
        return played
    }

    /// Takes the last move back; nil when no move was played.
    @discardableResult
    public mutating func takeBack() -> PlayedMove? {
        guard let last = moves.popLast() else { return nil }
        keys.removeLast()
        return last
    }

    // MARK: Rules

    /// How many times the current position has stood on the board, this time
    /// included. Two positions are the same when the pieces, the side to
    /// move, the castling rights and the en passant capture are the same.
    public var repetitions: Int {
        let key = position.positionKey
        return keys.count { $0 == key }
    }

    public var canClaimThreefoldRepetition: Bool { repetitions >= 3 }
    public var canClaimFiftyMoves: Bool { position.halfmoveClock >= 100 }

    /// The draw the side to move may claim now, repetition first.
    public var drawClaim: DrawClaim? {
        if canClaimThreefoldRepetition { return .threefoldRepetition }
        if canClaimFiftyMoves { return .fiftyMoveRule }
        return nil
    }

    /// What the board itself decides: mate, stalemate, or no way left to mate.
    public var boardEnding: GameEnding? {
        let position = position
        if position.legalMoves().isEmpty {
            return position.isCheck ? .checkmate(winner: position.turn.opposite) : .stalemate
        }
        return position.hasInsufficientMaterial ? .insufficientMaterial : nil
    }

    /// How the game has ended, or nil while it goes on. With `claimingDraws`
    /// a draw that could be claimed ends the game at once, which is how the
    /// ChessDesk site (and most game sites) play against a bot.
    public func ending(claimingDraws: Bool) -> GameEnding? {
        if let boardEnding { return boardEnding }
        guard claimingDraws, let drawClaim else { return nil }
        switch drawClaim {
        case .threefoldRepetition: return .threefoldRepetition
        case .fiftyMoveRule: return .fiftyMoveRule
        }
    }

    // MARK: PGN

    private static let sevenTags = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

    /// The game as PGN: the Seven Tag Roster first ("?" for what is not
    /// given), then the other tags, then the moves and the result. A game
    /// that does not start from the standard position carries its FEN.
    public func pgn(tags: [String: String] = [:]) -> String {
        var lines: [String] = []
        func line(_ name: String, _ value: String) {
            let escaped = value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
            lines.append("[\(name) \"\(escaped)\"]")
        }
        for name in Self.sevenTags {
            let fallback = name == "Date" ? "????.??.??" : name == "Result" ? "*" : "?"
            line(name, tags[name] ?? fallback)
        }
        for name in tags.keys.sorted() where !Self.sevenTags.contains(name) && name != "FEN" && name != "SetUp" {
            line(name, tags[name] ?? "")
        }
        if start != .start {
            line("FEN", start.fen)
            line("SetUp", "1")
        }

        var tokens: [String] = []
        for (index, played) in moves.enumerated() {
            if played.side == .white {
                tokens.append("\(played.moveNumber).")
            } else if index == 0 {
                tokens.append("\(played.moveNumber)...")
            }
            tokens.append(played.san)
        }
        tokens.append(tags["Result"] ?? "*")
        return lines.joined(separator: "\n") + "\n\n" + tokens.joined(separator: " ") + "\n"
    }
}
