import Foundation
import StockfishEngine

/// Stockfish held to a rating: what plays when Maia cannot. A port of the
/// site's `lib/play/engine/stockfish-bot-engine.ts`: `UCI_LimitStrength`,
/// `UCI_Elo` at the bot's `stockfishElo`, and the catalogue's time per move.
/// The catalogue already holds `stockfishElo` to what the engine accepts, so
/// a bot rated under that floor plays at the floor with this engine.
nonisolated struct StockfishBotEngine: BotEngine {
    let kind = BotEngineKind.stockfish
    /// The catalogue's `engines.stockfish.moveTimeMs`.
    let moveTime: Duration

    /// Starts the device engine; throws when its network is not in the app.
    static func start(_ info: StockfishEngineInfo) async throws -> StockfishBotEngine {
        guard let network = DeviceEngine.networkURL else {
            throw EngineError.networkMissing(StockfishEngine.networkName)
        }
        try await StockfishEngine.shared.start(network: network)
        return StockfishBotEngine(moveTime: .milliseconds(info.moveTimeMs))
    }

    func bestMove(fen: String, strength: BotStrength) async throws -> String {
        guard let move = try await StockfishEngine.shared.bestMove(fen: fen, limitedTo: strength.stockfishElo, moveTime: moveTime)
        else { throw BotEngineError.noMove }
        return move
    }
}

nonisolated extension BotEngineSelection {
    /// The engines of the app, set up as the catalogue says: Maia from the
    /// network it names, Stockfish from the app bundle. `maia: false` leaves
    /// Maia out, to check the fallback.
    static func device(_ engines: PlayEngines, maia: Bool = true, store: MaiaModelStore = .shared) -> BotEngineSelection {
        let info = engines.maia
        let stockfish = engines.stockfish
        return BotEngineSelection(
            // An engine this version does not know is skipped.
            order: engines.order.compactMap(BotEngineKind.init(rawValue:)),
            makeMaia: {
                guard maia else { throw BotEngineError.unavailable("Maia is switched off") }
                return try await store.engine(for: info)
            },
            makeStockfish: { try await StockfishBotEngine.start(stockfish) },
            loadBudget: .milliseconds(info.initBudgetMs),
            warmupBudget: .milliseconds(info.warmupBudgetMs)
        )
    }
}
