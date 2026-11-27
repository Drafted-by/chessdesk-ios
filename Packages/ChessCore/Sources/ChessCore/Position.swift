/// A standard chess position with full rules: legal moves, check, castling,
/// en passant, promotion. Value type; `playing(_:)` returns the next position.
public struct Position: Sendable, Hashable {
    public private(set) var board: [Piece?]
    public private(set) var turn: Side
    public private(set) var castling: CastlingRights
    public private(set) var enPassant: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let start = Position(fen: startFEN).unsafelyUnwrapped

    public subscript(square: Square) -> Piece? { board[square.index] }

    // MARK: FEN

    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (row, text) in ranks.enumerated() {
            var file = 0
            for character in text {
                if let skip = character.wholeNumberValue {
                    file += skip
                } else if let piece = Piece(fenCharacter: character), file < 8 {
                    board[(7 - row) * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        switch fields[1] {
        case "w": turn = .white
        case "b": turn = .black
        default: return nil
        }

        var rights: CastlingRights = []
        if fields.count > 2, fields[2] != "-" {
            for character in fields[2] {
                switch character {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: return nil
                }
            }
        }

        var enPassant: Square?
        if fields.count > 3, fields[3] != "-" {
            guard let square = Square(fields[3]) else { return nil }
            enPassant = square
        }

        self.board = board
        castling = rights
        self.enPassant = enPassant
        halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        fullmoveNumber = fields.count > 5 ? max(1, Int(fields[5]) ?? 1) : 1

        guard kingSquare(of: .white) != nil, kingSquare(of: .black) != nil else { return nil }
        dropImpossibleCastlingRights()
    }

    public var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var rights = ""
        if castling.contains(.whiteKingside) { rights += "K" }
        if castling.contains(.whiteQueenside) { rights += "Q" }
        if castling.contains(.blackKingside) { rights += "k" }
        if castling.contains(.blackQueenside) { rights += "q" }
        return [
            rows.joined(separator: "/"),
            turn == .white ? "w" : "b",
            rights.isEmpty ? "-" : rights,
            capturableEnPassant?.description ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }

    /// The en passant square, only when a pawn can legally capture there.
    /// FEN is written this way (as Lichess and the ChessDesk site do), so the
    /// same position always has the same text whatever the last move was.
    public var capturableEnPassant: Square? {
        guard let enPassant else { return nil }
        let forward = turn == .white ? 1 : -1
        for df in [-1, 1] {
            guard let from = Square(file: enPassant.file + df, rank: enPassant.rank - forward),
                  board[from.index] == Piece(turn, .pawn)
            else { continue }
            if leavesKingSafe(Move(from: from, to: enPassant)) { return enPassant }
        }
        return nil
    }

    /// The four fields that identify a position for training purposes
    /// (pieces, turn, castling, en passant), without the move counters.
    public var positionKey: String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    private mutating func dropImpossibleCastlingRights() {
        func holds(_ name: String, _ piece: Piece) -> Bool {
            Square(name).map { board[$0.index] == piece } ?? false
        }
        let whiteKing = holds("e1", Piece(.white, .king))
        let blackKing = holds("e8", Piece(.black, .king))
        if !whiteKing || !holds("h1", Piece(.white, .rook)) { castling.remove(.whiteKingside) }
        if !whiteKing || !holds("a1", Piece(.white, .rook)) { castling.remove(.whiteQueenside) }
        if !blackKing || !holds("h8", Piece(.black, .rook)) { castling.remove(.blackKingside) }
        if !blackKing || !holds("a8", Piece(.black, .rook)) { castling.remove(.blackQueenside) }
    }

    // MARK: Queries

    public func kingSquare(of side: Side) -> Square? {
        let king = Piece(side, .king)
        return board.firstIndex(of: king).map(Square.init(index:))
    }

    public var isCheck: Bool {
        guard let king = kingSquare(of: turn) else { return false }
        return isAttacked(king, by: turn.opposite)
    }

    public var isCheckmate: Bool { isCheck && legalMoves().isEmpty }
    public var isStalemate: Bool { !isCheck && legalMoves().isEmpty }

    public var outcome: Outcome? {
        if legalMoves().isEmpty {
            return isCheck ? .checkmate(winner: turn.opposite) : .stalemate
        }
        if hasInsufficientMaterial { return .insufficientMaterial }
        if halfmoveClock >= 100 { return .fiftyMoveRule }
        return nil
    }

    public var hasInsufficientMaterial: Bool {
        var minors: [(kind: PieceKind, light: Bool)] = []
        for square in Square.all {
            guard let piece = board[square.index], piece.kind != .king else { continue }
            guard piece.kind == .bishop || piece.kind == .knight else { return false }
            minors.append((piece.kind, square.isLight))
        }
        if minors.count <= 1 { return true }
        // Only bishops, all on the same square colour.
        return minors.allSatisfy { $0.kind == .bishop && $0.light == minors[0].light }
    }

    private static let knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let straights = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    private func piece(file: Int, rank: Int) -> Piece? {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return board[rank * 8 + file]
    }

    public func isAttacked(_ square: Square, by side: Side) -> Bool {
        let file = square.file
        let rank = square.rank

        // A pawn of `side` attacks towards its own forward direction.
        let pawnRank = rank - (side == .white ? 1 : -1)
        let pawn = Piece(side, .pawn)
        if piece(file: file - 1, rank: pawnRank) == pawn || piece(file: file + 1, rank: pawnRank) == pawn {
            return true
        }
        let knight = Piece(side, .knight)
        for (df, dr) in Self.knightSteps where piece(file: file + df, rank: rank + dr) == knight {
            return true
        }
        let king = Piece(side, .king)
        for (df, dr) in Self.kingSteps where piece(file: file + df, rank: rank + dr) == king {
            return true
        }
        return slides(from: square, Self.diagonals, hitting: side, .bishop)
            || slides(from: square, Self.straights, hitting: side, .rook)
    }

    private func slides(
        from square: Square,
        _ directions: [(Int, Int)],
        hitting side: Side,
        _ kind: PieceKind
    ) -> Bool {
        for (df, dr) in directions {
            var file = square.file + df
            var rank = square.rank + dr
            while (0..<8).contains(file), (0..<8).contains(rank) {
                if let found = board[rank * 8 + file] {
                    if found.side == side, found.kind == kind || found.kind == .queen { return true }
                    break
                }
                file += df
                rank += dr
            }
        }
        return false
    }

    // MARK: Move generation

    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for square in Square.all where board[square.index]?.side == turn {
            appendPseudoLegal(from: square, into: &moves)
        }
        return moves.filter(leavesKingSafe)
    }

    public func legalMoves(from square: Square) -> [Move] {
        guard board[square.index]?.side == turn else { return [] }
        var moves: [Move] = []
        appendPseudoLegal(from: square, into: &moves)
        return moves.filter(leavesKingSafe)
    }

    public func isLegal(_ move: Move) -> Bool {
        legalMoves(from: move.from).contains(move)
    }

    private func leavesKingSafe(_ move: Move) -> Bool {
        let next = applying(move)
        guard let king = next.kingSquare(of: turn) else { return false }
        return !next.isAttacked(king, by: turn.opposite)
    }

    private func appendPseudoLegal(from square: Square, into moves: inout [Move]) {
        guard let piece = board[square.index] else { return }
        switch piece.kind {
        case .pawn: appendPawnMoves(from: square, into: &moves)
        case .knight: appendSteps(Self.knightSteps, from: square, into: &moves)
        case .bishop: appendSlides(Self.diagonals, from: square, into: &moves)
        case .rook: appendSlides(Self.straights, from: square, into: &moves)
        case .queen: appendSlides(Self.diagonals + Self.straights, from: square, into: &moves)
        case .king:
            appendSteps(Self.kingSteps, from: square, into: &moves)
            appendCastling(from: square, into: &moves)
        }
    }

    private func appendSteps(_ steps: [(Int, Int)], from square: Square, into moves: inout [Move]) {
        for (df, dr) in steps {
            guard let target = Square(file: square.file + df, rank: square.rank + dr) else { continue }
            if board[target.index]?.side != turn { moves.append(Move(from: square, to: target)) }
        }
    }

    private func appendSlides(_ directions: [(Int, Int)], from square: Square, into moves: inout [Move]) {
        for (df, dr) in directions {
            var file = square.file + df
            var rank = square.rank + dr
            while let target = Square(file: file, rank: rank) {
                if let blocker = board[target.index] {
                    if blocker.side != turn { moves.append(Move(from: square, to: target)) }
                    break
                }
                moves.append(Move(from: square, to: target))
                file += df
                rank += dr
            }
        }
    }

    private func appendPawnMoves(from square: Square, into moves: inout [Move]) {
        let forward = turn == .white ? 1 : -1
        let startRank = turn == .white ? 1 : 6
        let lastRank = turn == .white ? 7 : 0

        func add(_ target: Square) {
            if target.rank == lastRank {
                for kind in [PieceKind.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: square, to: target, promotion: kind))
                }
            } else {
                moves.append(Move(from: square, to: target))
            }
        }

        if let one = Square(file: square.file, rank: square.rank + forward), board[one.index] == nil {
            add(one)
            if square.rank == startRank,
               let two = Square(file: square.file, rank: square.rank + 2 * forward),
               board[two.index] == nil {
                moves.append(Move(from: square, to: two))
            }
        }
        for df in [-1, 1] {
            guard let target = Square(file: square.file + df, rank: square.rank + forward) else { continue }
            if let victim = board[target.index] {
                if victim.side != turn { add(target) }
            } else if target == enPassant {
                moves.append(Move(from: square, to: target))
            }
        }
    }

    private func appendCastling(from square: Square, into moves: inout [Move]) {
        let rank = turn == .white ? 0 : 7
        guard square.file == 4, square.rank == rank else { return }
        let kingside: CastlingRights = turn == .white ? .whiteKingside : .blackKingside
        let queenside: CastlingRights = turn == .white ? .whiteQueenside : .blackQueenside
        let enemy = turn.opposite

        func empty(_ files: [Int]) -> Bool { files.allSatisfy { board[rank * 8 + $0] == nil } }
        func safe(_ files: [Int]) -> Bool {
            files.allSatisfy { !isAttacked(Square(index: rank * 8 + $0), by: enemy) }
        }

        if castling.contains(kingside), empty([5, 6]), safe([4, 5, 6]) {
            moves.append(Move(from: square, to: Square(index: rank * 8 + 6)))
        }
        if castling.contains(queenside), empty([1, 2, 3]), safe([4, 3, 2]) {
            moves.append(Move(from: square, to: Square(index: rank * 8 + 2)))
        }
    }

    // MARK: Playing moves

    /// The position after `move`, or nil when the move is not legal here.
    public func playing(_ move: Move) -> Position? {
        let move = normalized(move)
        return isLegal(move) ? applying(move) : nil
    }

    /// Some sources write castling as "king takes own rook" (e1h1). This maps
    /// that form to the usual king destination (e1g1); other moves are unchanged.
    public func normalized(_ move: Move) -> Move {
        guard let king = board[move.from.index], king.kind == .king,
              let rook = board[move.to.index], rook == Piece(king.side, .rook),
              move.from.rank == move.to.rank
        else { return move }
        let file = move.to.file > move.from.file ? 6 : 2
        return Move(from: move.from, to: Square(index: move.from.rank * 8 + file))
    }

    public func isCapture(_ move: Move) -> Bool {
        board[move.to.index] != nil || isEnPassant(move)
    }

    public func isEnPassant(_ move: Move) -> Bool {
        board[move.from.index]?.kind == .pawn && move.to == enPassant && move.from.file != move.to.file
    }

    public func isCastling(_ move: Move) -> Bool {
        board[move.from.index]?.kind == .king && abs(move.to.file - move.from.file) == 2
    }

    /// Where the rook goes for a castling move: (from, to), or nil.
    public func castlingRookMove(_ move: Move) -> (from: Square, to: Square)? {
        guard isCastling(move) else { return nil }
        let rank = move.from.rank
        return move.to.file == 6
            ? (Square(index: rank * 8 + 7), Square(index: rank * 8 + 5))
            : (Square(index: rank * 8), Square(index: rank * 8 + 3))
    }

    /// Applies a move without checking legality.
    private func applying(_ move: Move) -> Position {
        var next = self
        guard let piece = board[move.from.index] else { return next }
        let capture = isCapture(move)

        if isEnPassant(move) {
            next.board[move.from.rank * 8 + move.to.file] = nil
        }
        if let rook = castlingRookMove(move) {
            next.board[rook.to.index] = next.board[rook.from.index]
            next.board[rook.from.index] = nil
        }
        next.board[move.from.index] = nil
        next.board[move.to.index] = move.promotion.map { Piece(piece.side, $0) } ?? piece

        next.enPassant = nil
        if piece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassant = Square(index: (move.from.index + move.to.index) / 2)
        }

        for square in [move.from, move.to] {
            switch square.index {
            case 4: next.castling.subtract([.whiteKingside, .whiteQueenside])
            case 7: next.castling.remove(.whiteKingside)
            case 0: next.castling.remove(.whiteQueenside)
            case 60: next.castling.subtract([.blackKingside, .blackQueenside])
            case 63: next.castling.remove(.blackKingside)
            case 56: next.castling.remove(.blackQueenside)
            default: break
            }
        }

        next.halfmoveClock = piece.kind == .pawn || capture ? 0 : halfmoveClock + 1
        if turn == .black { next.fullmoveNumber += 1 }
        next.turn = turn.opposite
        return next
    }
}
