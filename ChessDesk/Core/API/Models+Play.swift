import Foundation

// Playing against the bots: the catalogue the server lists and the game the
// app sends back when it is over. Mirrors the site's `lib/play/authed-bots.ts`
// and `lib/play/actions.ts`.

/// Who may play a bot. The server decides; the app shows the gate.
nonisolated enum BotAccess: String, Codable, Hashable, Sendable {
    case free
    /// A (free) account is needed.
    case account
    case premium

    /// An access the app does not know yet is treated as the strictest it knows.
    init(from decoder: Decoder) throws {
        self = BotAccess(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .premium
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
    let country: String
    let rating: Int
    /// The id of its `BotTier`.
    let tier: String
    /// Portrait: a path on the site ("/bots/peru.webp") or a full URL.
    let avatar: String
    let tagline: String
    /// The move it likes to open with as White, in UCI.
    let firstMove: String?
    /// 0 (rock-solid) to 1 (wild): how loosely it samples its moves.
    let wildness: Double
    let access: BotAccess

    init(
        id: String, name: String, country: String, rating: Int, tier: String, avatar: String, tagline: String,
        firstMove: String? = nil, wildness: Double, access: BotAccess = .free
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.rating = rating
        self.tier = tier
        self.avatar = avatar
        self.tagline = tagline
        self.firstMove = firstMove
        self.wildness = wildness
        self.access = access
    }

    /// `access` may be absent: a bot the server lists without a gate is free.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        rating = try container.decode(Int.self, forKey: .rating)
        tier = try container.decode(String.self, forKey: .tier)
        avatar = try container.decode(String.self, forKey: .avatar)
        tagline = try container.decode(String.self, forKey: .tagline)
        firstMove = try container.decodeIfPresent(String.self, forKey: .firstMove)
        wildness = try container.decode(Double.self, forKey: .wildness)
        access = try container.decodeIfPresent(BotAccess.self, forKey: .access) ?? .free
    }
}

/// "Build your own opponent": any rating in a range, no character.
nonisolated struct CustomOpponent: Codable, Hashable, Sendable {
    let name: String
    let avatar: String
    let minRating: Int
    let maxRating: Int
    let step: Int
    let defaultRating: Int
    let wildness: Double
}

/// Where the Maia network is served. The file is fetched once and kept on
/// the device; it is never part of the app.
nonisolated struct MaiaModelInfo: Codable, Hashable, Sendable {
    let model: String
    let url: URL
}

nonisolated struct PlayCatalogue: Codable, Hashable, Sendable {
    let tiers: [BotTier]
    let bots: [PlayBot]
    let custom: CustomOpponent
    let maia: MaiaModelInfo?

    /// The roster by tier, weakest first, as the site lays it out.
    func bots(in tier: BotTier) -> [PlayBot] {
        bots.filter { $0.tier == tier.id }.sorted { $0.rating < $1.rating }
    }
}

/// A finished bot game, as the site's `saveBotGameAction` takes it.
nonisolated struct SaveBotGameRequest: Codable, Hashable, Sendable {
    let pgn: String
    /// "1-0", "0-1" or "1/2-1/2".
    let result: String
    /// "white" or "black".
    let userColor: String
    let botRating: Int
    let botName: String
    /// "maia-3" or "stockfish": the engine that really played.
    let engine: String
    let ply: Int
    let whiteName: String
    let blackName: String
    let whiteElo: Int?
    let blackElo: Int?
}

nonisolated struct SavedBotGame: Codable, Hashable, Sendable {
    let gameId: String
}
