import ChessCore
import Foundation

/// Reading a repertoire's move tree. A position is named by its path: the
/// moves from the start, in UCI, as the API names it. Pure.
nonisolated enum RepertoireTree {
    /// The moves the tree holds from the position reached by `path`; nil
    /// when the path leaves the tree.
    static func children(at path: [String], in tree: [RepertoireNode]) -> [RepertoireNode]? {
        var siblings = tree
        for uci in path {
            guard let node = siblings.first(where: { $0.uci == uci }) else { return nil }
            siblings = node.children
        }
        return siblings
    }

    /// The nodes along `path`, as far as the tree follows it.
    static func nodes(along path: [String], in tree: [RepertoireNode]) -> [RepertoireNode] {
        var siblings = tree
        var found: [RepertoireNode] = []
        for uci in path {
            guard let node = siblings.first(where: { $0.uci == uci }) else { break }
            found.append(node)
            siblings = node.children
        }
        return found
    }

    static func node(at path: [String], in tree: [RepertoireNode]) -> RepertoireNode? {
        let found = nodes(along: path, in: tree)
        return found.count == path.count ? found.last : nil
    }

    /// `path` cut where it leaves the tree: where to stand after the tree changed.
    static func longestPrefix(of path: [String], in tree: [RepertoireNode]) -> [String] {
        nodes(along: path, in: tree).map(\.uci)
    }

    /// The main continuation from a position: first child after first child.
    static func mainLine(from path: [String], in tree: [RepertoireNode]) -> [RepertoireNode] {
        var line: [RepertoireNode] = []
        var next = children(at: path, in: tree)?.first
        while let node = next {
            line.append(node)
            next = node.children.first
        }
        return line
    }

    /// A line is a path to a leaf, as the free allowance counts them.
    static func lineCount(_ tree: [RepertoireNode]) -> Int {
        tree.reduce(0) { $0 + ($1.children.isEmpty ? 1 : lineCount($1.children)) }
    }

    static func moveCount(_ tree: [RepertoireNode]) -> Int {
        tree.reduce(0) { $0 + 1 + moveCount($1.children) }
    }

    /// The glyph of a move, by its NAG, as the builder of the site writes
    /// them (`components/repertoire/current-line-view.tsx`).
    static let glyphs: [(nag: Int, text: String)] = [(1, "!"), (3, "!!"), (5, "!?"), (6, "?!"), (2, "?"), (4, "??")]

    static func glyph(_ nags: [Int]) -> String {
        nags.compactMap { nag in glyphs.first { $0.nag == nag }?.text }.joined()
    }

    /// "3." before a white move; "3…" before a black move that opens a row.
    static func number(ply: Int, opensRow: Bool) -> String? {
        let number = (ply + 1) / 2
        if !ply.isMultiple(of: 2) { return "\(number)." }
        return opensRow ? "\(number)…" : nil
    }

    /// "3. Bc4" or "3… Bc5": a move named on its own.
    static func numbered(_ node: RepertoireNode) -> String {
        "\(number(ply: node.ply, opensRow: true) ?? "") \(node.san)\(glyph(node.nags))"
    }

    // MARK: The outline, for the tree view

    struct OutlineMove: Hashable, Sendable, Identifiable {
        let path: [String]
        let san: String
        let ply: Int
        let glyph: String
        let hasNote: Bool
        /// The row starts with this move: its number is always written.
        let opensRow: Bool

        var id: [String] { path }
    }

    /// A run of moves with no choice in it. A row one step deeper is an
    /// alternative at the point where the row above ends.
    struct OutlineRow: Hashable, Sendable, Identifiable {
        let depth: Int
        let moves: [OutlineMove]

        var id: [String] { moves.first?.path ?? [] }
    }

    /// The whole tree as indented rows: each row runs until the tree
    /// branches, then every continuation opens a row of its own below it,
    /// the main one first.
    static func outline(_ tree: [RepertoireNode]) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        for root in tree { emit(root, path: [], depth: 0, into: &rows) }
        return rows
    }

    private static func emit(_ first: RepertoireNode, path: [String], depth: Int, into rows: inout [OutlineRow]) {
        var moves: [OutlineMove] = []
        var path = path
        var node = first
        while true {
            path.append(node.uci)
            moves.append(OutlineMove(
                path: path, san: node.san, ply: node.ply, glyph: glyph(node.nags),
                hasNote: !node.comments.isEmpty, opensRow: moves.isEmpty
            ))
            guard node.children.count == 1 else { break }
            node = node.children[0]
        }
        rows.append(OutlineRow(depth: depth, moves: moves))
        guard node.children.count > 1 else { return }
        for child in node.children { emit(child, path: path, depth: depth + 1, into: &rows) }
    }

    // MARK: Changes (what the sample data applies; the server does its own)

    /// The tree with `line` played from the start: the moves already there
    /// are followed, the others added. Nil when a move is illegal.
    static func adding(line: [String], to tree: [RepertoireNode], startFen: String) -> (tree: [RepertoireNode], added: Int)? {
        guard let start = Position(fen: startFen) else { return nil }
        let startPly = (start.fullmoveNumber - 1) * 2 + (start.turn == .white ? 0 : 1)
        var added = 0
        func insert(_ moves: ArraySlice<String>, into siblings: [RepertoireNode], position: Position, ply: Int) -> [RepertoireNode]? {
            guard let uci = moves.first else { return siblings }
            guard let parsed = Move(uci: uci), let san = position.san(for: parsed), let next = position.playing(parsed)
            else { return nil }
            let canonical = position.normalized(parsed).uci
            var siblings = siblings
            if let index = siblings.firstIndex(where: { $0.uci == canonical }) {
                guard let children = insert(moves.dropFirst(), into: siblings[index].children, position: next, ply: ply + 1)
                else { return nil }
                siblings[index] = siblings[index].with(children: children)
            } else {
                guard let children = insert(moves.dropFirst(), into: [], position: next, ply: ply + 1) else { return nil }
                added += 1
                siblings.append(RepertoireNode(
                    san: san, uci: canonical, fen: next.fen, ply: ply + 1, comments: [], nags: [], shapes: [], children: children
                ))
            }
            return siblings
        }
        guard let result = insert(line[...], into: tree, position: start, ply: startPly) else { return nil }
        return (result, added)
    }

    /// The tree without the move at the end of `path` and what follows it.
    static func removing(path: [String], from tree: [RepertoireNode]) -> [RepertoireNode]? {
        guard let uci = path.first, let index = tree.firstIndex(where: { $0.uci == uci }) else { return nil }
        var tree = tree
        if path.count == 1 {
            tree.remove(at: index)
        } else {
            guard let children = removing(path: Array(path.dropFirst()), from: tree[index].children) else { return nil }
            tree[index] = tree[index].with(children: children)
        }
        return tree
    }

    /// The tree with the node at `path` replaced by `change(node)`.
    static func updating(
        path: [String], in tree: [RepertoireNode], _ change: (RepertoireNode) -> RepertoireNode
    ) -> [RepertoireNode]? {
        guard let uci = path.first, let index = tree.firstIndex(where: { $0.uci == uci }) else { return nil }
        var tree = tree
        if path.count == 1 {
            tree[index] = change(tree[index])
        } else {
            guard let children = updating(path: Array(path.dropFirst()), in: tree[index].children, change) else { return nil }
            tree[index] = tree[index].with(children: children)
        }
        return tree
    }
}

nonisolated extension RepertoireNode {
    func with(children: [RepertoireNode]) -> RepertoireNode {
        RepertoireNode(san: san, uci: uci, fen: fen, ply: ply, comments: comments, nags: nags, shapes: shapes, children: children)
    }

    func with(comments: [String], nags: [Int]) -> RepertoireNode {
        RepertoireNode(san: san, uci: uci, fen: fen, ply: ply, comments: comments, nags: nags, shapes: shapes, children: children)
    }

    /// The moves below this one, itself not counted.
    var descendantCount: Int { RepertoireTree.moveCount(children) }
}
