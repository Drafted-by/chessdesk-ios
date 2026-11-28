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
        try await send("GET", PlayEndpoints.catalogue, token: token)
    }

    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail {
        try await send("POST", PlayEndpoints.games, token: token, body: game)
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
