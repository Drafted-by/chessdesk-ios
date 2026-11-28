/// The moves of an analysis: a main line and its variations, each node one
/// move with the position after it. The first child of a node continues the
/// main line (or the variation it belongs to); the others are side lines.
///
/// Value type: every edit returns or mutates a copy, so a screen can keep the
/// previous tree for undo and tests can compare trees.
public struct MoveTree: Sendable, Hashable {
    public struct NodeID: Sendable, Hashable, Comparable, CustomStringConvertible {
        public let raw: Int
        public static func < (lhs: NodeID, rhs: NodeID) -> Bool { lhs.raw < rhs.raw }
        public var description: String { "#\(raw)" }
    }

    public struct Node: Sendable, Hashable {
        public let id: NodeID
        public let parent: NodeID?
        /// Nil for the root, the starting position.
        public let move: Move?
        /// "" for the root.
        public let san: String
        /// The position after the move (the start for the root).
        public let position: Position
        /// Half-moves from the start of the game: 1 for White's first move.
        /// The root holds the ply before the first move.
        public let ply: Int
        /// The first child continues this line; the others are variations.
        public internal(set) var children: [NodeID]
        /// A note written after the move in the PGN, without its braces.
        public var comment: String?

        /// "12." before a White move, "12..." before a Black move.
        public var moveNumberText: String {
            let number = (ply + 1) / 2
            return ply % 2 == 1 ? "\(number)." : "\(number)..."
        }

        /// The side that played this node's move.
        public var side: Side { ply % 2 == 1 ? .white : .black }
    }

    public let root: NodeID
    public private(set) var nodes: [NodeID: Node]
    /// PGN tag pairs in the order they were read or set.
    public var headers: [PGNTag]
    private var nextID: Int

    public init(start: Position = .start) {
        let root = NodeID(raw: 0)
        self.root = root
        let ply = (start.fullmoveNumber - 1) * 2 + (start.turn == .white ? 0 : 1)
        nodes = [root: Node(id: root, parent: nil, move: nil, san: "", position: start, ply: ply, children: [], comment: nil)]
        headers = []
        nextID = 1
    }

    public var start: Position { self[root].position }

    public subscript(id: NodeID) -> Node {
        nodes[id].unsafelyUnwrapped
    }

    public func contains(_ id: NodeID) -> Bool { nodes[id] != nil }

    // MARK: Editing

    /// Plays `move` after `parent`. When that move is already a child, the
    /// existing node is returned and nothing changes; otherwise the move
    /// becomes a new last child (the main line when it is the first).
    /// Nil when the move is illegal.
    @discardableResult
    public mutating func add(_ move: Move, after parent: NodeID) -> NodeID? {
        guard let node = nodes[parent] else { return nil }
        let move = node.position.normalized(move)
        if let existing = node.children.first(where: { nodes[$0]?.move == move }) { return existing }
        guard let san = node.position.san(for: move), let next = node.position.playing(move) else { return nil }
        let id = NodeID(raw: nextID)
        nextID += 1
        nodes[id] = Node(id: id, parent: parent, move: move, san: san, position: next, ply: node.ply + 1, children: [], comment: nil)
        nodes[parent]?.children.append(id)
        return id
    }

    /// Plays a SAN move after `parent`; nil when it does not name a legal move.
    @discardableResult
    public mutating func add(san: String, after parent: NodeID) -> NodeID? {
        guard let move = nodes[parent]?.position.move(san: san) else { return nil }
        return add(move, after: parent)
    }

    /// Moves the variation that holds `id` one level up: at the nearest point
    /// where its line leaves its parent's first line, it takes the place of
    /// that first line. Nothing happens on the main line.
    public mutating func promote(_ id: NodeID) {
        var current = id
        while let parent = nodes[current]?.parent {
            let siblings = self[parent].children
            if let index = siblings.firstIndex(of: current), index > 0 {
                nodes[parent]?.children.remove(at: index)
                nodes[parent]?.children.insert(current, at: 0)
                return
            }
            current = parent
        }
    }

    /// Promotes the line of `id` until it is the main line.
    public mutating func makeMainLine(_ id: NodeID) {
        while !isOnMainLine(id) { promote(id) }
    }

    /// Removes `id` and every move after it. Returns its parent, where the
    /// cursor should go. Nothing happens to the root.
    @discardableResult
    public mutating func delete(_ id: NodeID) -> NodeID? {
        guard let node = nodes[id], let parent = node.parent else { return nil }
        nodes[parent]?.children.removeAll { $0 == id }
        var stack = [id]
        while let next = stack.popLast() {
            stack.append(contentsOf: nodes[next]?.children ?? [])
            nodes[next] = nil
        }
        return parent
    }

    public mutating func setComment(_ comment: String?, on id: NodeID) {
        let trimmed = comment?.trimmingWhitespace()
        nodes[id]?.comment = trimmed?.isEmpty == false ? trimmed : nil
    }

    // MARK: Reading

    /// The nodes from the root (excluded) to `id` (included).
    public func path(to id: NodeID) -> [NodeID] {
        var path: [NodeID] = []
        var current: NodeID? = id
        while let node = current.flatMap({ nodes[$0] }), node.parent != nil {
            path.append(node.id)
            current = node.parent
        }
        return path.reversed()
    }

    /// The line that continues from `id` by first children, `id` excluded.
    public func continuation(after id: NodeID) -> [NodeID] {
        var line: [NodeID] = []
        var current = id
        while let next = nodes[current]?.children.first {
            line.append(next)
            current = next
        }
        return line
    }

    /// The main line, root excluded.
    public var mainLine: [NodeID] { continuation(after: root) }

    public func isOnMainLine(_ id: NodeID) -> Bool {
        var current = id
        while let parent = nodes[current]?.parent {
            if self[parent].children.first != current { return false }
            current = parent
        }
        return true
    }

    /// The last move of the line through `id`: where "last move" goes.
    public func end(of id: NodeID) -> NodeID {
        continuation(after: id).last ?? id
    }

    /// Whether the line through `id` branches anywhere: tells a lone line
    /// from a tree in the move list.
    public var hasVariations: Bool {
        nodes.values.contains { $0.children.count > 1 }
    }

    /// The SAN moves of the main line.
    public var mainLineSAN: [String] { mainLine.map { self[$0].san } }
}

/// One PGN tag pair: `[White "Ana"]`.
public struct PGNTag: Sendable, Hashable {
    public var name: String
    public var value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}
