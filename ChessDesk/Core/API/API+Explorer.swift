import Foundation

/// The opening explorer of the player's own imported games. Needs an account.
nonisolated protocol ExplorerAPI {
    /// Games per colour and the free cap: what the screen needs before any position.
    func explorerSummary(token: String) async throws -> ExplorerSummary
    /// One position of the player's tree. `path` is the moves in SAN, as
    /// `moves[].san` gives them; `games` is how many of the games reaching the
    /// position come back (the server's default when nil, 50 at most).
    func explorerPosition(
        path: [String], filters: ExplorerFilters, games: Int?, token: String
    ) async throws -> ExplorerPosition
}

extension LiveAPI: ExplorerAPI {
    func explorerSummary(token: String) async throws -> ExplorerSummary {
        try await exchange("GET", "explorer", token: token)
    }

    func explorerPosition(
        path: [String], filters: ExplorerFilters, games: Int?, token: String
    ) async throws -> ExplorerPosition {
        try await exchange(
            "GET", "explorer/position",
            query: Self.explorerQuery(path: path, filters: filters, games: games), token: token
        )
    }

    /// The query of `GET /explorer/position`: only what differs from the
    /// server's defaults is sent.
    static func explorerQuery(path: [String], filters: ExplorerFilters, games: Int?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "side", value: filters.side == .black ? "black" : "white")]
        if !path.isEmpty { query.append(URLQueryItem(name: "path", value: path.joined(separator: ","))) }
        let timeClasses = ExplorerFilters.timeClasses.filter(filters.timeClasses.contains)
        if !timeClasses.isEmpty { query.append(URLQueryItem(name: "tc", value: timeClasses.joined(separator: ","))) }
        if filters.rated != .all { query.append(URLQueryItem(name: "rated", value: filters.rated.rawValue)) }
        if let from = filters.dateFrom { query.append(URLQueryItem(name: "from", value: from)) }
        if let to = filters.dateTo { query.append(URLQueryItem(name: "to", value: to)) }
        if let min = filters.opponentMin { query.append(URLQueryItem(name: "min", value: String(min))) }
        if let max = filters.opponentMax { query.append(URLQueryItem(name: "max", value: String(max))) }
        if let source = filters.source { query.append(URLQueryItem(name: "source", value: source.rawValue)) }
        if let games { query.append(URLQueryItem(name: "games", value: String(games))) }
        return query
    }
}

/// On sample data the explorer walks the games of `FixturePlayer`, synthetic.
extension FixtureAPI: ExplorerAPI {
    func explorerSummary(token: String) async throws -> ExplorerSummary {
        try await Task.sleep(for: delay)
        return await FixturePlayer.current.explorerSummary()
    }

    func explorerPosition(
        path: [String], filters: ExplorerFilters, games: Int?, token: String
    ) async throws -> ExplorerPosition {
        try await Task.sleep(for: delay)
        return try await FixturePlayer.current.explorerPosition(path: path, filters: filters, games: games)
    }
}
