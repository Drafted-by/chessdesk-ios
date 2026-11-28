import ChessCore
import Foundation
import Testing
@testable import ChessDesk

/// Test stubs implement what they exercise; the repertoire and explorer
/// calls default to "not stubbed", like the games calls in `ReviewTests`.
extension RepertoiresAPI {
    private var notStubbed: APIError { .server(status: 401, code: "unauthorized", message: "Not stubbed.") }
    func repertoires(token: String) async throws -> RepertoireList { throw notStubbed }
    func createRepertoire(name: String, color: String, token: String) async throws -> RepertoireDetail { throw notStubbed }
    func repertoire(id: String, token: String) async throws -> RepertoireDetail { throw notStubbed }
    func renameRepertoire(id: String, name: String, token: String) async throws { throw notStubbed }
    func deleteRepertoire(id: String, token: String) async throws { throw notStubbed }
    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail { throw notStubbed }
    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail { throw notStubbed }
    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail { throw notStubbed }
    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport { throw notStubbed }
    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed { throw notStubbed }
    func repertoireSession(id: String, mode: SessionMode?, token: String) async throws -> CourseSession { throw notStubbed }
    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition {
        throw notStubbed
    }
    func repertoireAdherence(id: String, token: String) async throws -> RepertoireAdherence { throw notStubbed }
}

extension ExplorerAPI {
    private var notStubbed: APIError { .server(status: 401, code: "unauthorized", message: "Not stubbed.") }
    func explorerSummary(token: String) async throws -> ExplorerSummary { throw notStubbed }
    func explorerPosition(
        path: [String], filters: ExplorerFilters, games: Int?, token: String
    ) async throws -> ExplorerPosition { throw notStubbed }
}

/// The site's OpenAPI contract, read as the server publishes it.
nonisolated enum Contract {
    static func document() throws -> [String: Any] {
        let bundle = Bundle(for: ContractToken.self)
        let url = try #require(bundle.url(forResource: "openapi-v1", withExtension: "json", subdirectory: "contracts"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func schemas() throws -> [String: Any] {
        let components = try #require(try document()["components"] as? [String: Any])
        return try #require(components["schemas"] as? [String: Any])
    }

    static func paths() throws -> [String: Any] {
        try #require(try document()["paths"] as? [String: Any])
    }

    /// The names of the query parameters of an operation.
    static func queryParameters(_ path: String, _ method: String) throws -> Set<String> {
        let operations = try #require(try paths()[path] as? [String: Any], "\(path) is in the contract")
        let operation = try #require(operations[method] as? [String: Any], "\(method) \(path) is in the contract")
        let parameters = operation["parameters"] as? [[String: Any]] ?? []
        return Set(parameters.filter { $0["in"] as? String == "query" }.compactMap { $0["name"] as? String })
    }

    private static func resolve(_ schema: [String: Any], _ schemas: [String: Any]) -> (name: String?, schema: [String: Any]) {
        if let reference = schema["$ref"] as? String, let name = reference.split(separator: "/").last,
           let target = schemas[String(name)] as? [String: Any] {
            return (String(name), target)
        }
        return (nil, schema)
    }

    private static func types(_ schema: [String: Any]) -> [String] {
        (schema["type"] as? [String]) ?? (schema["type"] as? String).map { [$0] } ?? ["object"]
    }

    static func isNullable(_ schema: [String: Any]) -> Bool {
        if types(schema).contains("null") { return true }
        let options = (schema["anyOf"] as? [[String: Any]]) ?? (schema["oneOf"] as? [[String: Any]]) ?? []
        return options.contains { types($0) == ["null"] }
    }

    /// An example built from the required fields of a schema. With `nulls`,
    /// every field that may be null is null: what an optional must survive.
    /// A schema that holds itself (a move and the moves after it) is given
    /// `depth` levels.
    static func example(_ name: String, nulls: Bool = false, depth: Int = 2) throws -> Any {
        let schemas = try schemas()
        let schema = try #require(schemas[name] as? [String: Any], "schema \(name) is in the contract")
        return example(schema, schemas, nulls: nulls, depth: depth, inside: [name: 1])
    }

    private static func example(
        _ raw: [String: Any], _ schemas: [String: Any], nulls: Bool, depth: Int, inside: [String: Int]
    ) -> Any {
        let (name, schema) = resolve(raw, schemas)
        var inside = inside
        if let name, raw["$ref"] != nil { inside[name, default: 0] += 1 }
        if nulls, isNullable(schema) { return NSNull() }
        if let options = (schema["anyOf"] as? [[String: Any]]) ?? (schema["oneOf"] as? [[String: Any]]) {
            let chosen = options.first { types($0) != ["null"] } ?? options[0]
            return example(chosen, schemas, nulls: nulls, depth: depth, inside: inside)
        }
        if let values = schema["enum"] as? [Any], let first = values.first { return first }
        if let constant = schema["const"] { return constant }
        switch types(schema).first { $0 != "null" } ?? "object" {
        case "string":
            if (schema["format"] as? String) == "date-time" { return "2027-01-25T16:29:15.210Z" }
            return "text"
        case "integer", "number": return 1
        case "boolean": return true
        case "array":
            let items = schema["items"] as? [String: Any] ?? [:]
            // A schema inside itself stops at `depth`.
            if let reference = (items["$ref"] as? String)?.split(separator: "/").last,
               (inside[String(reference)] ?? 0) >= depth { return [Any]() }
            return [example(items, schemas, nulls: nulls, depth: depth, inside: inside)]
        default:
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            var object: [String: Any] = [:]
            for name in schema["required"] as? [String] ?? [] {
                object[name] = properties[name].map { example($0, schemas, nulls: nulls, depth: depth, inside: inside) }
            }
            return object
        }
    }

    /// What is wrong with a JSON value read against a schema of the contract:
    /// a required field missing, a wrong type, a value outside an enum.
    static func problems(in value: Any, against name: String) throws -> [String] {
        let schemas = try schemas()
        let schema = try #require(schemas[name] as? [String: Any], "schema \(name) is in the contract")
        var found: [String] = []
        check(value, schema, schemas, at: name, into: &found)
        return found
    }

    private static func check(_ value: Any, _ raw: [String: Any], _ schemas: [String: Any], at path: String, into found: inout [String]) {
        let schema = resolve(raw, schemas).schema
        if value is NSNull {
            if !isNullable(schema) { found.append("\(path): null is not allowed") }
            return
        }
        if let options = (schema["anyOf"] as? [[String: Any]]) ?? (schema["oneOf"] as? [[String: Any]]) {
            let chosen = options.first { types($0) != ["null"] } ?? options[0]
            return check(value, chosen, schemas, at: path, into: &found)
        }
        if let allowed = schema["enum"] as? [Any] {
            if !allowed.contains(where: { "\($0)" == "\(value)" }) { found.append("\(path): \(value) is not in \(allowed)") }
            return
        }
        switch types(schema).first { $0 != "null" } ?? "object" {
        case "string":
            guard let text = value as? String else { return found.append("\(path): not a string") }
            if (schema["format"] as? String) == "date-time", APICoding.parseDate(text) == nil { found.append("\(path): not a date") }
            if let pattern = schema["pattern"] as? String, text.range(of: pattern, options: .regularExpression) == nil {
                found.append("\(path): \(text) does not match \(pattern)")
            }
        case "integer":
            guard let number = value as? NSNumber, !isBoolean(value), number.doubleValue == number.doubleValue.rounded() else {
                return found.append("\(path): not an integer")
            }
            range(number.doubleValue, schema, at: path, into: &found)
        case "number":
            guard let number = value as? NSNumber, !isBoolean(value) else { return found.append("\(path): not a number") }
            range(number.doubleValue, schema, at: path, into: &found)
        case "boolean":
            if !isBoolean(value) { found.append("\(path): not a boolean") }
        case "array":
            guard let items = value as? [Any] else { return found.append("\(path): not an array") }
            let itemSchema = schema["items"] as? [String: Any] ?? [:]
            for (index, item) in items.enumerated() { check(item, itemSchema, schemas, at: "\(path)[\(index)]", into: &found) }
        default:
            guard let object = value as? [String: Any] else { return found.append("\(path): not an object") }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for name in schema["required"] as? [String] ?? [] where object[name] == nil {
                // Swift leaves a nil out when it encodes; the server writes null.
                if let property = properties[name], isNullable(resolve(property, schemas).schema) { continue }
                found.append("\(path).\(name): missing")
            }
            for (name, property) in properties {
                if let inner = object[name] { check(inner, property, schemas, at: "\(path).\(name)", into: &found) }
            }
        }
    }

    /// JSON's true and false, which Foundation also reads as the numbers 1 and 0.
    private static func isBoolean(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    private static func range(_ number: Double, _ schema: [String: Any], at path: String, into found: inout [String]) {
        if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, number < minimum { found.append("\(path): \(number) is under \(minimum)") }
        if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, number > maximum { found.append("\(path): \(number) is over \(maximum)") }
    }

    /// A model of the app as the JSON it stands for.
    static func json(_ value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: APICoding.encoder.encode(value))
    }
}

private final class ContractToken {}

/// Moves in SAN from the start position, as UCI.
nonisolated func uci(_ san: String) -> [String] { FixtureData.uciLine(san) }

/// A small tree for the tests: lines given in SAN.
nonisolated func tree(_ lines: String...) -> [RepertoireNode] {
    var tree: [RepertoireNode] = []
    for line in lines {
        tree = RepertoireTree.adding(line: uci(line), to: tree, startFen: Position.startFEN)?.tree ?? tree
    }
    return tree
}

nonisolated func detail(
    id: String = "rep1", name: String = "My White", color: String = "WHITE", tree: [RepertoireNode],
    editable: Bool = true, lineLimit: Int? = 20
) -> RepertoireDetail {
    let lines = RepertoireTree.lineCount(tree)
    return RepertoireDetail(
        id: id, name: name, color: color, deck: "repertoire:\(id)", lines: lines, moves: RepertoireTree.moveCount(tree),
        progress: DeckProgress(lines: lines, learned: 0, newLines: lines, dueLines: 0, solidLines: 0, dueMoves: 0, moves: 0),
        editable: editable, updatedAt: Date(timeIntervalSince1970: 1_800_000_000), startFen: Position.startFEN, tree: tree,
        truncated: false, rootComment: "", pgn: "", lineLimit: lineLimit, pace: .init(perDay: 3, newLeft: 3)
    )
}

/// A server holding one repertoire, in memory: it applies the changes the
/// way the site does, records every call, and can be told to refuse the next
/// write or to let another device change the tree first. Like the site, it
/// answers castling as the king taking its rook and reads either spelling.
nonisolated final class RepertoireServer: RepertoiresAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RepertoireDetail
    private var calls: [String] = []
    private var refusal: APIError?
    private var concurrent: [RepertoireNode]?
    private var positionFailure: APIError?
    private var positionDelay: Duration = .zero
    private var unanswered: [String: [String]] = [:]

    init(_ detail: RepertoireDetail) {
        stored = detail
    }

    var log: [String] { lock.withLock { calls } }
    /// The repertoire as it is kept: castling in the board's spelling.
    var current: RepertoireDetail { lock.withLock { stored } }

    private func stored(_ path: [String]) -> [String] { CastlingSpelling.board(path: path, from: Position.startFEN) }
    /// The positions asked for, as "e2e4,e7e5" ("" is the start).
    var positionsAsked: [String] { log.filter { $0.hasPrefix("position ") }.map { String($0.dropFirst("position ".count)) } }
    var reads: Int { log.count { $0 == "read" } }

    /// The next write answers with this error instead of being applied.
    func refuseNextWrite(_ error: APIError, treeBecomes other: [RepertoireNode]? = nil) {
        lock.withLock {
            refusal = error
            concurrent = other
        }
    }

    func failPositions(_ error: APIError?) { lock.withLock { positionFailure = error } }
    func slowPositions(_ delay: Duration) { lock.withLock { positionDelay = delay } }
    func leaveUnanswered(_ ucis: [String], at path: [String]) { lock.withLock { unanswered[path.joined(separator: ",")] = ucis } }

    private func write(_ call: String, _ change: (RepertoireDetail) throws -> [RepertoireNode]) throws -> RepertoireDetail {
        try lock.withLock {
            calls.append(call)
            if let refusal {
                self.refusal = nil
                if let concurrent {
                    stored = detail(tree: concurrent)
                    self.concurrent = nil
                }
                throw refusal
            }
            stored = detail(name: stored.name, tree: try change(stored), editable: stored.editable, lineLimit: stored.lineLimit)
            return stored.treeSpelled
        }
    }

    func repertoire(id: String, token: String) async throws -> RepertoireDetail {
        lock.withLock {
            calls.append("read")
            return stored.treeSpelled
        }
    }

    func renameRepertoire(id: String, name: String, token: String) async throws {
        _ = try write("rename \(name)") { $0.tree }
        lock.withLock { stored = detail(name: name, tree: stored.tree) }
    }

    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail {
        try write("add \(line.joined(separator: ","))") { current in
            guard let next = RepertoireTree.adding(line: line, to: current.tree, startFen: current.startFen) else {
                throw APIError.server(status: 422, code: "request_failed", message: "That move is not legal in this position.")
            }
            return next.tree
        }
    }

    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail {
        try write("annotate \(path.joined(separator: ",")) [\(comment ?? "-")] \(glyph)") { current in
            guard !path.isEmpty else { return current.tree }
            let changed = RepertoireTree.updating(path: self.stored(path), in: current.tree) { node in
                let nags: [Int] = switch glyph {
                case .keep: node.nags
                case .clear: []
                case let .set(nag): [nag]
                }
                return node.with(comments: comment.map { $0.isEmpty ? [] : [$0] } ?? node.comments, nags: nags)
            }
            guard let changed else { throw APIError.server(status: 404, code: "not_found", message: "That move is not in the repertoire.") }
            return changed
        }
    }

    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail {
        try write("remove \(path.joined(separator: ","))") { current in
            guard let next = RepertoireTree.removing(path: self.stored(path), from: current.tree) else {
                throw APIError.server(status: 404, code: "not_found", message: "That move is not in the repertoire.")
            }
            return next
        }
    }

    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport {
        let read = FixturePGN.read(pgn)
        let detail = try write("import") { _ in read.tree }
        return RepertoireImport(repertoire: detail, merged: read.merged, skipped: read.skipped)
    }

    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed {
        let detail = try write("seed") { _ in tree("d4 d5 c4", "d4 Nf6 c4") }
        return RepertoireSeed(repertoire: detail, games: 12)
    }

    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition {
        let (failure, delay, tree, gaps) = lock.withLock {
            calls.append("position \(path.joined(separator: ","))")
            return (positionFailure, positionDelay, stored.tree, unanswered[path.joined(separator: ",")] ?? [])
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        let path = stored(path)
        var position = Position.start
        var san: [String] = []
        for uci in path {
            guard let move = Move(uci: uci), let name = position.san(for: move), let next = position.playing(move) else { break }
            san.append(name)
            position = next
        }
        let children = RepertoireTree.children(at: path, in: tree)
        func move(_ uci: String, _ freq: Double) -> RepertoirePosition.Move {
            let name = Move(uci: uci).flatMap { position.san(for: $0) } ?? uci
            return .init(san: name, uci: uci, games: 100, white: 50, draws: 10, black: 40, freq: freq, whiteScore: 0.55, opening: nil)
        }
        let played = (children ?? []).map { move($0.uci, 0.5) } + gaps.map { move($0, 0.2) }
        return RepertoirePosition(
            fen: position.fen, path: path, san: san, inRepertoire: children != nil, covered: (children ?? []).map(\.uci),
            masters: .init(total: 1000, moves: played), lichess: .init(total: 5000, moves: played), ratings: ratings ?? "1000",
            ratingBands: [.init(ratings: "1000", label: "1000–1200"), .init(ratings: "1400", label: "1400–1600")],
            mine: [], opponentToMove: !path.count.isMultiple(of: 2),
            gaps: gaps.map { .init(san: move($0, 0.2).san, uci: $0, freq: 0.2, opening: nil) },
            advice: .init(kind: "keep", title: "Keep going", detail: "Add your move.", moveNumber: path.count / 2 + 1)
        )
        .treeSpelled
    }
}

/// Waits for a condition that scheduled work brings about.
func settled(_ done: () -> Bool) async {
    for _ in 0..<600 where !done() {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}
