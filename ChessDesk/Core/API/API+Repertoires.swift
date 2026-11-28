import Foundation

/// The player's own repertoires: the list, the move tree and its changes,
/// training sessions, the statistics of a position, and the games checked
/// against a repertoire. Every call needs an account.
///
/// `403 premium_required` is the paywall. `422 request_failed` is a rule
/// saying no, a write that lost against another one included: its message is
/// shown and the repertoire is read again.
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

extension LiveAPI {
    /// One exchange with the server for the routes of a feature file: the
    /// transport of `LiveAPI` is private to `ChessDeskAPI.swift`.
    func exchange<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        token: String?,
        timeout: TimeInterval = 20
    ) async throws -> Response {
        var request = request(method, path, query: query, token: token)
        request.timeoutInterval = timeout
        return try await exchange(request)
    }

    func exchange<Response: Decodable>(
        _ method: String,
        _ path: String,
        token: String?,
        body: some Encodable,
        timeout: TimeInterval = 20
    ) async throws -> Response {
        var request = request(method, path, query: [], token: token)
        request.timeoutInterval = timeout
        request.httpBody = try APICoding.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await exchange(request)
    }

    private func exchange<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var request = request
        request.url = request.url.map(Self.strictQuery)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreadable }
        return try Self.decode(status: http.statusCode, data: data)
    }

    /// A "+" is legal in a query, but the server reads it as a space: a check
    /// in a SAN path ("Bb5+") must travel as "%2B".
    static func strictQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.percentEncodedQuery, query.contains("+")
        else { return url }
        components.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? url
    }
}

extension LiveAPI: RepertoiresAPI {
    func repertoires(token: String) async throws -> RepertoireList {
        try await exchange("GET", "repertoires", token: token)
    }

    func createRepertoire(name: String, color: String, token: String) async throws -> RepertoireDetail {
        try await exchange("POST", "repertoires", token: token, body: CreateRepertoireRequest(name: name, color: color))
    }

    func repertoire(id: String, token: String) async throws -> RepertoireDetail {
        try await exchange("GET", "repertoires/\(id)", token: token)
    }

    func renameRepertoire(id: String, name: String, token: String) async throws {
        let _: OkResponse = try await exchange(
            "PATCH", "repertoires/\(id)", token: token, body: RenameRepertoireRequest(name: name)
        )
    }

    func deleteRepertoire(id: String, token: String) async throws {
        let _: OkResponse = try await exchange("DELETE", "repertoires/\(id)", token: token)
    }

    func addRepertoireLine(id: String, line: [String], token: String) async throws -> RepertoireDetail {
        try await exchange("POST", "repertoires/\(id)/moves", token: token, body: RepertoireLineRequest(line: line))
    }

    func annotateRepertoireMove(
        id: String, path: [String], comment: String?, glyph: GlyphChange, token: String
    ) async throws -> RepertoireDetail {
        try await exchange(
            "PATCH", "repertoires/\(id)/moves", token: token,
            body: AnnotateRepertoireMoveRequest(path: path, comment: comment, glyph: glyph)
        )
    }

    func removeRepertoireMove(id: String, path: [String], token: String) async throws -> RepertoireDetail {
        try await exchange(
            "DELETE", "repertoires/\(id)/moves",
            query: [URLQueryItem(name: "path", value: path.joined(separator: ","))], token: token
        )
    }

    func importRepertoirePGN(id: String, pgn: String, token: String) async throws -> RepertoireImport {
        // A course PGN can hold hundreds of games to merge.
        try await exchange(
            "PUT", "repertoires/\(id)/pgn", token: token, body: ImportRepertoirePgnRequest(pgn: pgn), timeout: 60
        )
    }

    func seedRepertoire(id: String, token: String) async throws -> RepertoireSeed {
        try await exchange("POST", "repertoires/\(id)/seed", token: token, timeout: 60)
    }

    func repertoireSession(id: String, mode: SessionMode?, token: String) async throws -> CourseSession {
        let query = mode.map { [URLQueryItem(name: "mode", value: $0.rawValue)] } ?? []
        return try await exchange("GET", "repertoires/\(id)/session", query: query, token: token)
    }

    func repertoirePosition(id: String, path: [String], ratings: String?, token: String) async throws -> RepertoirePosition {
        try await exchange(
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
        try await exchange("GET", "repertoires/\(id)/adherence", token: token)
    }
}

/// On sample data the repertoires answer for a signed-in player who does not
/// exist: `FixtureOpenings`, synthetic. The token is not looked at.
extension FixtureAPI: RepertoiresAPI {
    private func player<Value: Sendable>(
        _ work: @Sendable (FixtureOpenings) async throws -> Value
    ) async throws -> Value {
        try await Task.sleep(for: delay)
        return try await work(FixtureOpenings.current)
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
