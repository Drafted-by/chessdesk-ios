/// Why a PGN could not be read.
public enum PGNError: Error, Sendable, Hashable {
    /// The `[FEN]` tag does not describe a position.
    case badFEN(String)
    /// A move the rules refuse, with its number as written: "12... Nf6".
    case illegalMove(String)
    /// A ")" without its "(" or a variation before any move.
    case badVariation

    public var message: String {
        switch self {
        case .badFEN: "The FEN tag of this PGN does not describe a position."
        case let .illegalMove(move): "\(move) is not a legal move in this position."
        case .badVariation: "A variation in this PGN is not closed or opens before any move."
        }
    }
}

extension MoveTree {
    /// Reads a PGN with its tags, comments and variations (nested to any
    /// depth). Move numbers, glyphs and NAGs are skipped. Only the first game
    /// of a file is read. Bare moves ("e4 e5 Nf3") are a PGN too.
    public init(pgn: String) throws(PGNError) {
        let tokens = PGNLexer.tokens(pgn)
        var headers: [PGNTag] = []
        for token in tokens {
            guard case let .tag(name, value) = token else { break }
            headers.append(PGNTag(name, value))
        }
        var start = Position.start
        if let fen = headers.first(where: { $0.name.lowercased() == "fen" })?.value {
            guard let position = Position(fen: fen) else { throw .badFEN(fen) }
            start = position
        }

        var tree = MoveTree(start: start)
        tree.headers = headers
        var current = tree.root
        var resume: [NodeID] = []
        var sawMove = false

        tokens: for token in tokens {
            switch token {
            case .tag:
                // A tag after the moves starts the next game.
                if sawMove { break tokens }
            case let .move(san):
                sawMove = true
                guard let id = tree.add(san: san, after: current) else {
                    let before = tree[current]
                    let number = (before.ply + 2) / 2
                    let prefix = before.ply % 2 == 0 ? "\(number)." : "\(number)..."
                    throw .illegalMove("\(prefix) \(san)")
                }
                current = id
            case .open:
                // A variation replaces the move just played.
                guard let parent = tree[current].parent else { throw .badVariation }
                resume.append(current)
                current = parent
            case .close:
                guard let back = resume.popLast() else { throw .badVariation }
                current = back
            case let .comment(text):
                guard current != tree.root else { continue }
                let joined = [tree[current].comment, text].compactMap { $0 }.joined(separator: " ")
                tree.setComment(joined, on: current)
            case .result:
                if resume.isEmpty { break tokens }
            }
        }
        guard resume.isEmpty else { throw .badVariation }
        self = tree
    }

    /// The tree as PGN: tags, then the moves with their variations and
    /// comments, wrapped at 80 columns, then the result.
    public func pgn(result: String? = nil) -> String {
        let outcome = result ?? headers.first { $0.name == "Result" }?.value ?? "*"
        var tags = headers.filter { !["Result", "SetUp", "FEN"].contains($0.name) }
        if start.fen != Position.startFEN {
            tags.append(PGNTag("SetUp", "1"))
            tags.append(PGNTag("FEN", start.fen))
        }
        tags.append(PGNTag("Result", outcome))

        var words: [String] = []
        writeMoves(after: root, forceNumber: true, into: &words)
        words.append(outcome)

        let header = tags.map { "[\($0.name) \"\(Self.escape($0.value))\"]" }.joined(separator: "\n")
        return header + "\n\n" + Self.wrap(words, width: 80) + "\n"
    }

    /// Only the moves: "1. e4 e5 (1... c5) 2. Nf3", no tags or result.
    public var movetext: String {
        var words: [String] = []
        writeMoves(after: root, forceNumber: true, into: &words)
        return words.joined(separator: " ")
    }

    private func writeMoves(after parent: NodeID, forceNumber: Bool, into words: inout [String]) {
        let children = self[parent].children
        guard let main = children.first else { return }
        write(main, forceNumber: forceNumber, into: &words)
        for variation in children.dropFirst() {
            var inner: [String] = []
            write(variation, forceNumber: true, into: &inner)
            writeMoves(after: variation, forceNumber: self[variation].comment != nil, into: &inner)
            inner[0] = "(" + inner[0]
            inner[inner.count - 1] += ")"
            words.append(contentsOf: inner)
        }
        writeMoves(after: main, forceNumber: children.count > 1 || self[main].comment != nil, into: &words)
    }

    private func write(_ id: NodeID, forceNumber: Bool, into words: inout [String]) {
        let node = self[id]
        if node.side == .white || forceNumber { words.append(node.moveNumberText) }
        words.append(node.san)
        if let comment = node.comment {
            let clean = comment.replacingOccurrences(of: "}", with: ")")
            words.append(contentsOf: ("{" + clean + "}").split(separator: " ").map(String.init))
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func wrap(_ words: [String], width: Int) -> String {
        var lines: [String] = []
        var line = ""
        for word in words {
            if line.isEmpty {
                line = word
            } else if line.count + 1 + word.count > width {
                lines.append(line)
                line = word
            } else {
                line += " " + word
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }
}

/// PGN text to tokens. Lenient: unknown characters are skipped, move numbers
/// may be glued to their move ("12.e4"), glyphs stuck to a move are dropped.
enum PGNLexer {
    enum Token: Equatable {
        case tag(String, String)
        case move(String)
        case comment(String)
        case open, close
        case result(String)
    }

    static let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "½-½", "*"]

    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0
        var word = ""

        func flush() {
            defer { word = "" }
            guard let token = moveToken(word) else { return }
            tokens.append(token)
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "[":
                flush()
                var inner = ""
                index += 1
                while index < characters.count, characters[index] != "]" {
                    // An escaped quote inside a value.
                    if characters[index] == "\\", index + 1 < characters.count {
                        index += 1
                    }
                    inner.append(characters[index])
                    index += 1
                }
                if let tag = tag(inner) { tokens.append(tag) }
            case "{":
                flush()
                var inner = ""
                index += 1
                while index < characters.count, characters[index] != "}" {
                    inner.append(characters[index])
                    index += 1
                }
                let comment = inner.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !comment.isEmpty { tokens.append(.comment(comment)) }
            case ";":
                flush()
                while index < characters.count, !characters[index].isNewline { index += 1 }
            case "(":
                flush()
                tokens.append(.open)
            case ")":
                flush()
                tokens.append(.close)
            case _ where character.isWhitespace:
                flush()
            default:
                word.append(character)
            }
            index += 1
        }
        flush()
        return tokens
    }

    private static func tag(_ inner: String) -> Token? {
        let trimmed = inner.trimmingWhitespace()
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return nil }
        let name = String(trimmed[..<space])
        var value = String(trimmed[space...]).trimmingWhitespace()
        if value.hasPrefix("\"") { value.removeFirst() }
        if value.hasSuffix("\"") { value.removeLast() }
        return name.isEmpty ? nil : .tag(name, value)
    }

    private static func moveToken(_ raw: String) -> Token? {
        if results.contains(raw) { return .result(raw) }
        var token = Substring(raw)
        // "12." "12..." "12.e4" "12...Nf6"
        while let first = token.first, first.isNumber { token.removeFirst() }
        while token.first == "." { token.removeFirst() }
        if token.isEmpty || token.hasPrefix("$") { return nil }
        // Glyphs: "!", "?", "!?" and the check marks SAN reading ignores.
        while let last = token.last, "!?".contains(last) { token.removeLast() }
        guard let first = token.first, first.isLetter || token.hasPrefix("0-0") else { return nil }
        if token == "e.p." { return nil }
        return .move(String(token))
    }
}

extension String {
    fileprivate func replacingOccurrences(of target: String, with replacement: String) -> String {
        guard !target.isEmpty else { return self }
        var result = ""
        var rest = Substring(self)
        while let range = rest.range(of: target) {
            result += rest[..<range.lowerBound]
            result += replacement
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}

extension Substring {
    fileprivate func range(of target: String) -> Range<Substring.Index>? {
        var start = startIndex
        while start < endIndex {
            if self[start...].hasPrefix(target) {
                return start..<index(start, offsetBy: target.count)
            }
            start = index(after: start)
        }
        return nil
    }
}
