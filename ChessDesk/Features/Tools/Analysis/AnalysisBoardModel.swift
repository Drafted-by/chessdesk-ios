import ChessCore
import Foundation
import Observation

/// A free board: moves for both sides from any position, side lines kept in
/// a tree, the engine following the position on screen. Ported from the
/// site's analysis board (`apps/web/components/analysis-board/analysis-core.tsx`),
/// with variations, which the site's board does not keep.
@Observable
final class AnalysisBoardModel {
    private(set) var tree: MoveTree
    private(set) var cursor: MoveTree.NodeID {
        didSet { follow() }
    }

    var orientation: Side
    private(set) var opening: Opening?
    let engine: LiveAnalysisModel

    @ObservationIgnored var onMovePlayed: (_ capture: Bool) -> Void = { _ in }
    @ObservationIgnored private var book: OpeningBook?

    init(
        tree: MoveTree = MoveTree(),
        cursor: MoveTree.NodeID? = nil,
        orientation: Side = .white,
        engine: LiveAnalysisModel = LiveAnalysisModel(),
        book: OpeningBook? = nil
    ) {
        self.tree = tree
        self.cursor = cursor.flatMap { tree.contains($0) ? $0 : nil } ?? tree.root
        self.orientation = orientation
        self.engine = engine
        self.book = book
        follow()
    }

    // MARK: The position on screen

    var node: MoveTree.Node { tree[cursor] }
    var position: Position { node.position }
    var lastMove: Move? { node.move }
    var fen: String { position.fen }
    var pgn: String { tree.pgn() }

    var canGoBack: Bool { node.parent != nil }
    var canGoForward: Bool { !node.children.isEmpty }
    var isOnMainLine: Bool { tree.isOnMainLine(cursor) }

    /// "Checkmate. White wins." and the like (the site's `terminalMessage`).
    var outcomeText: String? {
        switch position.outcome {
        case let .checkmate(winner): "Checkmate. \(winner == .white ? "White" : "Black") wins."
        case .stalemate: "Stalemate. Draw."
        case .insufficientMaterial: "Draw by insufficient material."
        case .fiftyMoveRule, nil: nil
        }
    }

    // MARK: Moves

    /// Plays a move from the board: a new move becomes a side line when the
    /// position already has a continuation, an existing one is followed.
    @discardableResult
    func play(_ move: Move) -> Bool {
        let before = position
        guard let id = tree.add(move, after: cursor) else { return false }
        cursor = id
        onMovePlayed(before.isCapture(before.normalized(move)))
        return true
    }

    /// Plays an engine line up to `count` moves (the whole line by default).
    func play(_ line: EngineLine, count: Int? = nil) {
        guard line.san.count == line.moves.count, engine.position == position else { return }
        let moves = line.moves.prefix(count ?? line.moves.count)
        var at = cursor
        for move in moves {
            guard let next = tree.add(move, after: at) else { break }
            at = next
        }
        guard at != cursor else { return }
        let capture = tree[at].parent.map { tree[$0].position.isCapture(tree[at].move!) } ?? false
        cursor = at
        onMovePlayed(capture)
    }

    func go(to id: MoveTree.NodeID) {
        guard tree.contains(id) else { return }
        cursor = id
    }

    func back() {
        if let parent = node.parent { cursor = parent }
    }

    func forward() {
        if let next = node.children.first { cursor = next }
    }

    func toStart() { cursor = tree.root }

    func toEnd() { cursor = tree.end(of: cursor) }

    func flip() { orientation = orientation.opposite }

    // MARK: The tree

    func promote(_ id: MoveTree.NodeID) { tree.promote(id) }

    func makeMainLine(_ id: MoveTree.NodeID) { tree.makeMainLine(id) }

    /// Removes a move and what follows it; the cursor steps back when it was
    /// on the removed part.
    func delete(_ id: MoveTree.NodeID) {
        let onRemoved = tree.path(to: cursor).contains(id)
        guard let parent = tree.delete(id) else { return }
        if onRemoved { cursor = parent }
    }

    /// A fresh board from `position`, white at the bottom unless Black is to move.
    func reset(to position: Position = .start) {
        tree = MoveTree(start: position)
        cursor = tree.root
    }

    /// Loads a game or a position; the cursor goes to the start, as the site does.
    func load(_ loaded: AnalysisInput.Loaded) {
        tree = loaded.tree
        cursor = loaded.tree.root
        if let side = loaded.orientation { orientation = side }
    }

    /// A game's moves as the main line, with its players and result kept
    /// for the PGN, and the node of move `ply` (the start for 0).
    static func tree(from line: GameLine, ply: Int) -> (MoveTree, MoveTree.NodeID) {
        var tree = MoveTree(start: Position(fen: line.startFEN) ?? .start)
        tree.headers = ["Event", "Site", "Date", "White", "Black", "Result", "WhiteElo", "BlackElo"].compactMap { name in
            line.headers[name].map { PGNTag(name, $0) }
        }
        var at = tree.root
        var cursor = tree.root
        for (index, played) in line.moves.enumerated() {
            guard let next = tree.add(played.move, after: at) else { break }
            at = next
            if index + 1 == ply { cursor = next }
        }
        return (tree, cursor)
    }

    // MARK: Opening name and engine

    /// Names the opening once the book is read; the board works before.
    func loadOpenings() async {
        guard book == nil else { return }
        book = await OpeningBook.bundled()
        follow()
    }

    private func follow() {
        engine.show(position)
        opening = currentOpening()
    }

    private func currentOpening() -> Opening? {
        guard let book else { return nil }
        // Openings are named from the standard start only.
        guard tree.start.fen == Position.startFEN else { return book.identify(position: position) }
        let path = tree.path(to: cursor)
        let sans = path.map { tree[$0].san }
        // The deepest position of the line that has a name, then the
        // longest named start of the line.
        for length in stride(from: path.count, through: 1, by: -1) {
            if let opening = book.positionMatch(moves: Array(sans.prefix(length)), position: tree[path[length - 1]].position) {
                return opening
            }
        }
        return book.longestStart(of: sans)
    }
}

/// What a player pastes into the board: a FEN or a PGN, read as the site's
/// best-move finder reads it (`apps/web/lib/next-move/position.ts`).
nonisolated enum AnalysisInput {
    struct Loaded {
        let tree: MoveTree
        /// The side to put at the bottom; nil to keep the board as it is.
        let orientation: Side?
    }

    enum SideToMove: Hashable { case asWritten, white, black }

    enum Failure: Error, Equatable {
        case empty
        case badFEN
        case impossible(SetupProblem)
        case pgn(PGNError)

        var message: String {
            switch self {
            case .empty: "Paste a FEN or a PGN first."
            case .badFEN: "That FEN could not be read. Check the piece placement."
            case let .impossible(problem): problem.message
            case let .pgn(error): error.message
            }
        }
    }

    /// A FEN has eight ranks separated by slashes in its first field.
    static func looksLikeFEN(_ text: String) -> Bool {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first ?? ""
        return first.split(separator: "/", omittingEmptySubsequences: false).count == 8 && !first.contains(".")
    }

    static func read(_ text: String, sideToMove: SideToMove = .asWritten) -> Result<Loaded, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        if looksLikeFEN(trimmed) {
            let side: String? = switch sideToMove {
            case .asWritten: nil
            case .white: "w"
            case .black: "b"
            }
            guard let fen = composeFEN(trimmed, sideToMove: side), let position = Position(fen: fen) else {
                return .failure(.badFEN)
            }
            if let problem = position.setupProblem { return .failure(.impossible(problem)) }
            return .success(Loaded(tree: MoveTree(start: position), orientation: position.turn))
        }
        do {
            let tree = try MoveTree(pgn: trimmed)
            if let problem = tree.start.setupProblem { return .failure(.impossible(problem)) }
            return .success(Loaded(tree: tree, orientation: nil))
        } catch {
            return .failure(.pgn(error))
        }
    }

    /// A full FEN from a placement or a whole FEN, with the side to move
    /// given or kept (the site's `composeFen`). Castling, en passant and the
    /// counters the rules cannot read become "-", "-", 0 and 1. Shredder
    /// castling letters of a standard game (HAha) are read as KQkq.
    static func composeFEN(_ text: String, sideToMove: String?) -> String? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        guard let placement = parts.first else { return nil }
        let written = parts.count > 1 && (parts[1] == "w" || parts[1] == "b") ? parts[1] : "w"
        let side = sideToMove ?? written
        guard Position(fen: "\(placement) \(side) - - 0 1") != nil else { return nil }

        var castling = "-"
        if parts.count > 2 {
            let shredder: [Character: Character] = ["H": "K", "A": "Q", "h": "k", "a": "q"]
            let field = String(parts[2].map { shredder[$0] ?? $0 })
            let valid = field.range(of: "^(K?Q?k?q?)$", options: .regularExpression) != nil && !field.isEmpty
            castling = valid ? field : "-"
        }
        let enPassant = parts.count > 3 && parts[3].range(of: "^[a-h][36]$", options: .regularExpression) != nil ? parts[3] : "-"
        let halfmove = parts.count > 4 && parts[4].range(of: "^\\d{1,4}$", options: .regularExpression) != nil ? parts[4] : "0"
        let fullmove = parts.count > 5 && parts[5].range(of: "^[1-9]\\d{0,4}$", options: .regularExpression) != nil ? parts[5] : "1"
        return "\(placement) \(side) \(castling) \(enPassant) \(halfmove) \(fullmove)"
    }
}
