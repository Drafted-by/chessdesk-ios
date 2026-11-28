import Foundation

/// The player's own repertoires: the list, the move tree and its changes,
/// training sessions, the statistics of a position, and the games checked
/// against a repertoire. Every call needs an account.
///
/// `403 premium_required` is the paywall. `422 request_failed` is a rule
/// saying no: its message is shown. `409 request_failed` on the three writes
/// of `/moves` is a change that lost against another one: nothing was
/// written, the repertoire is read again and the change sent once more.
/// `429` (with `Retry-After`) limits the position look-ups, the PGN import
/// and the seed.
///
/// Every `uci` of an answer spells castling as the king taking its rook
/// (`e1h1`); requests may use either spelling. See `CastlingSpelling`.
nonisolated protocol RepertoiresAPI {
    func repertoires(token: String) async throws -> RepertoireList
    /// An empty repertoire for one colour ("WHITE" or "BLACK").
    func createRepertoire(name: String, color: String, token: String) async throws -> RepertoireDetail
    func repertoire(id: String, token: String) async throws -> RepertoireDetail
    func renameRepertoire(id: String, name: String, token: String) async throws
    func deleteRepertoire(id: String, token: String) async throws
    /// Adds a move or a whole line, given from the start position in UCI. The
    /// moves already in the tree are followed, the others added.
    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail
    /// Sets the note and the glyph of the move at the end of `path`; an empty
    /// path is the note before the first move.
    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail
    /// Removes the move at the end of `path` and everything played after it.
    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail
    /// Replaces the tree with the games of a PGN, merged.
    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport
    /// Replaces the tree with the openings the player really plays with this colour.
    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed
    /// A Learn or Review session, in the shape of a course session. Without a
    /// mode the server chooses: the review when moves are due, else Learn.
    func repertoireSession(id: String, mode: SessionMode?, token: String) async throws -> CourseSession
    /// Statistics for the position reached by `path`. Limited to 60 a minute
    /// per player: callers debounce. `ratings` is a Lichess rating band, nil
    /// for the server's default.
    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition
    /// The latest games against the repertoire. Premium.
    func repertoireAdherence(id: String, token: String) async throws -> RepertoireAdherence
}

extension LiveAPI: RepertoiresAPI {
    func repertoires(token: String) async throws -> RepertoireList {
        try await send("GET", "repertoires", token: token)
    }

    func createRepertoire(name: String, color: String, token: String) async throws -> RepertoireDetail {
        try await send("POST", "repertoires", token: token, body: CreateRepertoireRequest(name: name, color: color))
    }

    func repertoire(id: String, token: String) async throws -> RepertoireDetail {
        try await send("GET", "repertoires/\(id)", token: token)
    }

    func renameRepertoire(id: String, name: String, token: String) async throws {
        let _: OkResponse = try await send(
            "PATCH", "repertoires/\(id)", token: token, body: RenameRepertoireRequest(name: name)
        )
    }

    func deleteRepertoire(id: String, token: String) async throws {
        let _: OkResponse = try await send("DELETE", "repertoires/\(id)", token: token)
    }

    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail {
        try await send("POST", "repertoires/\(id)/moves", token: token, body: RepertoireLineRequest(line: line))
    }

    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail {
        try await send(
            "PATCH", "repertoires/\(id)/moves", token: token,
            body: AnnotateRepertoireMoveRequest(path: path, comment: comment, glyph: glyph)
        )
    }

    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail {
        try await send(
            "DELETE", "repertoires/\(id)/moves",
            query: [URLQueryItem(name: "path", value: path.joined(separator: ","))], token: token
        )
    }

    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport {
        // A course PGN can hold hundreds of games to merge.
        try await send(
            "PUT", "repertoires/\(id)/pgn", token: token, body: ImportRepertoirePgnRequest(pgn: pgn), timeout: 60
        )
    }

    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed {
        try await send("POST", "repertoires/\(id)/seed", token: token, timeout: 60)
    }

    func repertoireSession(id: String, mode: SessionMode?, token: String) async throws -> CourseSession {
        let query = mode.map { [URLQueryItem(name: "mode", value: $0.rawValue)] } ?? []
        return try await send("GET", "repertoires/\(id)/session", query: query, token: token)
    }

    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition {
        try await send(
            "GET", "repertoires/\(id)/position",
            query: Self.repertoirePositionQuery(path: path, ratings: ratings), token: token
        )
    }

    /// The start position is an absent `path`, not an empty one.
    static func repertoirePositionQuery(path: [String], ratings: String?) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if !path.isEmpty { query.append(URLQueryItem(name: "path", value: path.joined(separator: ","))) }
        if let ratings { query.append(URLQueryItem(name: "ratings", value: ratings)) }
        return query
    }

    func repertoireAdherence(id: String, token: String) async throws -> RepertoireAdherence {
        try await send("GET", "repertoires/\(id)/adherence", token: token)
    }
}

/// On sample data the repertoires are the sample player's (`FixtureOpenings`,
/// synthetic); a guest is answered `unauthorized`, as by the server.
extension FixtureAPI: RepertoiresAPI {
    private func player<Value: Sendable>(
        _ work: @Sendable (FixtureOpenings) async throws -> Value
    ) async throws -> Value {
        try await Task.sleep(for: delay)
        return try await work(try signedInPlayer().openings)
    }

    func repertoires(token: String) async throws -> RepertoireList {
        try await player { await $0.list() }
    }

    func createRepertoire(name: String, color: String, token: String) async throws -> RepertoireDetail {
        try await player { try await $0.create(name: name, color: color) }
    }

    func repertoire(id: String, token: String) async throws -> RepertoireDetail {
        try await player { try await $0.detail(id) }
    }

    func renameRepertoire(id: String, name: String, token: String) async throws {
        try await player { try await $0.rename(id, to: name) }
    }

    func deleteRepertoire(id: String, token: String) async throws {
        try await player { try await $0.delete(id) }
    }

    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail {
        try await player { try await $0.addLine(id, line: line) }
    }

    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail {
        try await player { try await $0.annotate(id, path: path, comment: comment, glyph: glyph) }
    }

    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail {
        try await player { try await $0.remove(id, path: path) }
    }

    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport {
        try await player { try await $0.importPGN(id, pgn: pgn) }
    }

    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed {
        try await player { try await $0.seed(id) }
    }

    func repertoireSession(id: String, mode: SessionMode?, token: String) async throws -> CourseSession {
        try await player { try await $0.session(id, mode: mode) }
    }

    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition {
        try await player { try await $0.position(id, path: path, ratings: ratings) }
    }

    func repertoireAdherence(id: String, token: String) async throws -> RepertoireAdherence {
        try await player { try await $0.adherence(id) }
    }
}
