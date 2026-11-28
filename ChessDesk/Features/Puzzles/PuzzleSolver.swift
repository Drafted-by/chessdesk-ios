import ChessCore

/// How a puzzle line is played out, and what counts as found. A port of the
/// site's `apps/web/lib/puzzles/engine.ts` (`startPuzzle`, `submitMove`,
/// `hintSquare`), so a move is right in the app exactly when it is on the site:
///
/// - `moves[0]` is the opponent's setup move, played on start;
/// - the solver finds `moves[1]`, `moves[3]`…, and the replies `moves[2]`,
///   `moves[4]`… are played automatically;
/// - a solver move is right when it is the expected move **or any move that
///   gives checkmate**; a checkmate ends the puzzle at once.
///
/// What a wrong move costs is the caller's: the rated trainer lets the player
/// try again (the attempt is then a miss), a Woodpecker cycle ends the puzzle.
nonisolated struct PuzzleSolver: Sendable, Hashable {
    enum Result: Equatable {
        /// Not a legal move here.
        case illegal
        /// Legal, but neither the solution nor a mate. Nothing changed.
        case wrong
        /// Right; the opponent replied (when `reply` is set) and there is more to find.
        case correct(reply: Move?)
        /// Right, and the line is over.
        case solved
    }

    /// The puzzle's moves, as served (UCI).
    let line: [String]
    /// The side the player solves for.
    let solverSide: Side
    private(set) var position: Position
    /// Index in `line` of the next move the solver must find.
    private(set) var solutionIndex: Int
    /// The last move played on the board: setup, solver or reply.
    private(set) var lastMove: Move?
    private(set) var isSolved: Bool

    /// Starts a puzzle: plays the setup move so the position is the one to solve.
    /// Nil when the position cannot be read.
    init?(fen: String, moves: [String]) {
        guard let start = Position(fen: fen) else { return nil }
        line = moves
        if let first = moves.first, let setup = Move(uci: first), let after = start.playing(setup) {
            position = after
            solutionIndex = 1
            lastMove = start.normalized(setup)
            isSolved = false
        } else {
            // No setup move, or an unplayable one: solve from the position given.
            position = start
            solutionIndex = 0
            lastMove = nil
            isSolved = moves.isEmpty
        }
        solverSide = position.turn
    }

    init?(_ puzzle: Puzzle) { self.init(fen: puzzle.fen, moves: puzzle.moves) }
    init?(_ puzzle: WoodpeckerPuzzle) { self.init(fen: puzzle.fen, moves: puzzle.moves) }

    /// The next move the solver must find, in this position's terms.
    var expectedMove: Move? {
        guard !isSolved, solutionIndex < line.count, let move = Move(uci: line[solutionIndex]) else { return nil }
        return position.normalized(move)
    }

    /// The square the expected move starts from: what the Hint shows.
    var hintSquare: Square? { expectedMove?.from }

    /// The site has no promotion picker: a pawn reaching the last rank becomes
    /// the piece of the expected move when the squares match, a queen otherwise.
    /// The app's board asks; the answer is mapped the same way so the grade is the site's.
    func gradedMove(_ move: Move) -> Move {
        guard move.promotion != nil else { return move }
        if let expected = expectedMove, expected.from == move.from, expected.to == move.to, let piece = expected.promotion {
            return Move(from: move.from, to: move.to, promotion: piece)
        }
        return Move(from: move.from, to: move.to, promotion: .queen)
    }

    /// The position after `move` without judging it: what a wrong try looks like.
    func trying(_ move: Move) -> Position? { position.playing(gradedMove(move)) }

    /// Judges a solver move and, when right, plays it and the opponent's reply.
    mutating func submit(_ move: Move) -> Result {
        guard !isSolved, let expected = expectedMove else { return .wrong }
        let move = gradedMove(move)
        guard let after = position.playing(move) else { return .illegal }

        let exact = position.normalized(move) == expected
        let mate = after.isCheckmate
        guard exact || mate else { return .wrong }

        lastMove = position.normalized(move)
        position = after
        solutionIndex += 1

        // A mate ends the puzzle early, as does the end of the line.
        guard !mate, solutionIndex < line.count else {
            isSolved = true
            return .solved
        }

        var reply: Move?
        if let replyMove = Move(uci: line[solutionIndex]), let afterReply = position.playing(replyMove) {
            reply = position.normalized(replyMove)
            position = afterReply
            lastMove = reply
            solutionIndex += 1
        }
        if solutionIndex >= line.count {
            isSolved = true
            return .solved
        }
        return .correct(reply: reply)
    }
}
