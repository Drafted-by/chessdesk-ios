/// Why a position read from a FEN cannot be played or analysed, even though
/// its text is well formed. An engine given such a position may crash.
public enum SetupProblem: Sendable, Hashable {
    /// Each side needs exactly one king.
    case kings
    /// A pawn stands on the first or the last rank.
    case pawnOnBackRank
    /// The side that just moved left its own king in check.
    case sideNotToMoveInCheck

    /// A sentence a player can act on.
    public var message: String {
        switch self {
        case .kings: "Each side needs exactly one king."
        case .pawnOnBackRank: "A pawn cannot stand on the first or the last rank."
        case .sideNotToMoveInCheck: "The side that is not to move is in check."
        }
    }
}

extension Position {
    /// What makes this position impossible, or nil when it can be played.
    public var setupProblem: SetupProblem? {
        for side in Side.allCases where board.count(where: { $0 == Piece(side, .king) }) != 1 {
            return .kings
        }
        for square in Square.all where square.rank == 0 || square.rank == 7 {
            if board[square.index]?.kind == .pawn { return .pawnOnBackRank }
        }
        if let king = kingSquare(of: turn.opposite), isAttacked(king, by: turn) {
            return .sideNotToMoveInCheck
        }
        return nil
    }

    /// The SAN of an engine line given in UCI moves ("e2e4 e7e5"), as far as
    /// its moves are legal.
    public func sanLine(uci moves: [String]) -> [String] {
        var position = self
        var line: [String] = []
        for text in moves {
            guard let move = Move(uci: text), let san = position.san(for: move),
                  let next = position.playing(move)
            else { break }
            line.append(san)
            position = next
        }
        return line
    }
}
