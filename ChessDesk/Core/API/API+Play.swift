import Foundation

/// What playing the bots asks the backend: who they are and what moves them,
/// and keeping a finished game so it can be reviewed.
nonisolated protocol PlayAPI {
    /// `GET /api/v1/play/bots`: the roster and the engines. Open to guests; a
    /// token lets the server say whether this account may save its games.
    func playBots(token: String?) async throws -> PlayCatalogue
    /// `POST /api/v1/play/games`: saves a finished game to the account as a
    /// casual BOT game and answers with it, as `game(id:token:)` would.
    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail
    /// Whether this backend has accounts to save bot games to. When it has
    /// none, the app offers neither "save" nor "review" for them.
    var savesBotGames: Bool { get }
}

nonisolated enum PlayEndpoints {
    static let catalogue = "play/bots"
    static let games = "play/games"
}

extension LiveAPI: PlayAPI {
    var savesBotGames: Bool { true }

    func playBots(token: String?) async throws -> PlayCatalogue {
        try await play(request("GET", PlayEndpoints.catalogue, query: [], token: token))
    }

    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail {
        var request = request("POST", PlayEndpoints.games, query: [], token: token)
        request.httpBody = try APICoding.encoder.encode(game)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await play(request)
    }

    /// The transport of `LiveAPI` is private to its file; this is the same
    /// exchange, for the routes of this feature.
    private func play<Response: Decodable>(_ request: URLRequest) async throws -> Response {
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
}

extension FixtureAPI: PlayAPI {
    /// Sample data has no accounts, so nothing can be saved.
    var savesBotGames: Bool { false }

    /// The answer of production, as captured by `scripts/sync-play-bots.sh`.
    static func playCatalogue() throws -> PlayCatalogue {
        try LiveAPI.decode(status: 200, data: data("play-bots"))
    }

    func playBots(token: String?) async throws -> PlayCatalogue {
        try await Task.sleep(for: delay)
        return try Self.playCatalogue()
    }

    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail {
        throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.")
    }
}
