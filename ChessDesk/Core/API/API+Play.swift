import Foundation

/// What playing the bots asks the backend: who they are, and keeping a
/// finished game so it can be reviewed.
nonisolated protocol PlayAPI {
    /// The catalogue of bots. Open to guests; a token lets the server answer
    /// with what this account may play.
    func playBots(token: String?) async throws -> PlayCatalogue
    /// Saves a finished game to the account and answers with its id, the one
    /// `game(id:token:)` reads.
    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> SavedBotGame
    /// Whether this backend can save bot games at all. When it cannot, the
    /// app offers neither "save" nor "review" for them.
    var savesBotGames: Bool { get }
}

/// The catalogue and the save operation are being added to the app API on
/// the site's branch `feat/mobile-api-v1-puzzles-play`. Until that is merged
/// and served, the live client answers with the bundled catalogue (a mirror
/// of the site's roster, rebuilt by `scripts/sync-play-bots.sh`) and saves
/// nothing. Turn this on, and check the two paths below against the contract,
/// when the endpoints are live.
nonisolated enum PlayEndpoints {
    static let areLive = false
    static let catalogue = "play/bots"
    static let games = "play/games"
}

nonisolated enum BundledPlayCatalogue {
    static func load() throws -> PlayCatalogue {
        try LiveAPI.decode(status: 200, data: FixtureAPI.data("play-bots"))
    }
}

extension LiveAPI: PlayAPI {
    var savesBotGames: Bool { PlayEndpoints.areLive }

    func playBots(token: String?) async throws -> PlayCatalogue {
        guard PlayEndpoints.areLive else { return try BundledPlayCatalogue.load() }
        return try await play(request("GET", PlayEndpoints.catalogue, query: [], token: token))
    }

    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> SavedBotGame {
        guard PlayEndpoints.areLive else {
            throw APIError.server(status: 404, code: "not_found", message: "Bot games cannot be saved yet.")
        }
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

    func playBots(token: String?) async throws -> PlayCatalogue {
        try await Task.sleep(for: delay)
        return try BundledPlayCatalogue.load()
    }

    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> SavedBotGame {
        throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.")
    }
}
