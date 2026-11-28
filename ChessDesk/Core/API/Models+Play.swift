import Foundation

// Playing against the bots: the catalogue the server lists (`BotCatalogue` in
// the contract, `GET /api/v1/play/bots`) and the game the app sends back when
// it is over (`BotGameRequest`, `POST /api/v1/play/games`). Every number a
// bot plays with is read from here; the app holds no copy of its own.

/// Who may play a bot. The server decides; the app shows the gate.
nonisolated enum BotAccess: Hashable, Sendable {
    case free
    /// A (free) account is needed.
    case account
    case premium

    init(requiresAccount: Bool, requiresPremium: Bool) {
        self = requiresPremium ? .premium : requiresAccount ? .account : .free
    }
}

nonisolated struct BotTier: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    /// "900–1400 · a real fight"
    let blurb: String
}

/// A character of the roster: art, a rating, and light flavour over the same
/// rating-conditioned engine.
nonisolated struct PlayBot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// The country's name in English ("Peru", "South Korea").
    let country: String
    /// The id of its `BotTier`.
    let tier: String
    let rating: Int
    let tagline: String
    let portraitUrl: String
    /// An SVG on the site. The system does not draw SVG from the network, so
    /// the app shows the system's flag of `country` instead (`CountryFlag`).
    let flagUrl: String
    /// The move it likes to open with as White, in UCI.
    let firstMove: String?
    /// 0 (rock-solid) to 1 (wild): flavour, already folded into `temperature`.
    let wildness: Double
    /// How loosely Maia samples this bot's moves.
    let temperature: Double
    /// The `UCI_Elo` Stockfish is held to when it plays this bot.
    let stockfishElo: Int
    let requiresAccount: Bool
    let requiresPremium: Bool

    var access: BotAccess { BotAccess(requiresAccount: requiresAccount, requiresPremium: requiresPremium) }
}

/// "Build your own opponent": any rating in a range, no character.
nonisolated struct CustomOpponent: Codable, Hashable, Sendable {
    nonisolated struct Rating: Codable, Hashable, Sendable {
        let min: Int
        let max: Int
        let step: Int
        let `default`: Int
    }

    let id: String
    let name: String
    let portraitUrl: String
    let rating: Rating
    let wildness: Double
    let temperature: Double
    let requiresAccount: Bool
    let requiresPremium: Bool

    var access: BotAccess { BotAccess(requiresAccount: requiresAccount, requiresPremium: requiresPremium) }
}

/// Maia as the server describes it: where the network is fetched (once, then
/// kept on the device; it is never part of the app), what it takes and
/// answers, how a move is drawn from it, and how long it may take to start.
nonisolated struct MaiaEngineInfo: Codable, Hashable, Sendable {
    nonisolated struct Input: Codable, Hashable, Sendable {
        let name: String
        let dims: [Int]
        let type: String
    }

    nonisolated struct Sampling: Codable, Hashable, Sendable {
        let topP: Double
        let defaultTemperature: Double
    }

    let model: String
    let modelUrl: URL
    let inputs: [Input]
    let policyOutput: String
    let policySize: Int
    let history: Int
    let planeOrder: [String]
    let eloMax: Int
    let sampling: Sampling
    let initBudgetMs: Int
    let warmupBudgetMs: Int
}

/// Stockfish held to a rating, as the server describes it.
nonisolated struct StockfishEngineInfo: Codable, Hashable, Sendable {
    /// The range `UCI_Elo` accepts: the custom bot's rating is clamped to it.
    let minElo: Int
    let maxElo: Int
    let moveTimeMs: Int

    func elo(forRating rating: Int) -> Int {
        Swift.max(minElo, Swift.min(Swift.max(minElo, maxElo), rating))
    }
}

nonisolated struct PlayEngines: Codable, Hashable, Sendable {
    /// The engines to try, in order ("maia-3", "stockfish").
    let order: [String]
    let maia: MaiaEngineInfo
    let stockfish: StockfishEngineInfo
    /// After this long without an answer, a random legal move is played.
    let moveTimeoutMs: Int
}

nonisolated struct PlayCatalogue: Codable, Hashable, Sendable {
    let tiers: [BotTier]
    let bots: [PlayBot]
    let custom: CustomOpponent
    let engines: PlayEngines
    /// Whether the session that asked may save its games: false for a visitor.
    let canSaveGames: Bool

    /// The roster by tier, weakest first, as the site lays it out.
    func bots(in tier: BotTier) -> [PlayBot] {
        bots.filter { $0.tier == tier.id }.sorted { $0.rating < $1.rating }
    }
}

/// A finished bot game, as `POST /api/v1/play/games` takes it. The server
/// reads the opponent's name and rating from its own catalogue and counts the
/// moves from the PGN: the app only names the bot.
nonisolated struct SaveBotGameRequest: Codable, Hashable, Sendable {
    /// The id of the bot in the catalogue, or the custom bot's id.
    let bot: String
    /// The rating chosen for the custom bot; nil for a character.
    let rating: Int?
    /// "white" or "black".
    let userColor: String
    /// "1-0", "0-1" or "1/2-1/2".
    let result: String
    /// "maia-3" or "stockfish": the engine that really played.
    let engine: String
    let pgn: String
}
