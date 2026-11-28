import Foundation
import StockfishEngine

/// Stockfish held to a rating: what plays when Maia cannot. A port of the
/// site's `lib/play/engine/stockfish-bot-engine.ts`: `UCI_LimitStrength`,
/// `UCI_Elo` clamped to what the engine accepts (1320 to 3190), 300 ms a move.
/// A bot rated under 1320 therefore plays at 1320 with this engine.
nonisolated struct StockfishBotEngine: BotEngine {
    static let moveTime = Duration.milliseconds(300)

    let kind = BotEngineKind.stockfish

    /// Starts the device engine; throws when its network is not in the app.
    static func start() async throws -> StockfishBotEngine {
        guard let network = DeviceEngine.networkURL else {
            throw EngineError.networkMissing(StockfishEngine.networkName)
        }
        try await StockfishEngine.shared.start(network: network)
        return StockfishBotEngine()
    }

    func bestMove(fen: String, rating: Int, temperature: Double?) async throws -> String {
        guard let move = try await StockfishEngine.shared.bestMove(fen: fen, limitedTo: rating, moveTime: Self.moveTime)
        else { throw BotEngineError.noMove }
        return move
    }
}

nonisolated extension BotEngineSelection {
    /// The engines of the app: Maia from the catalogue's network, Stockfish
    /// from the app bundle.
    static func device(maia: MaiaModelInfo?, store: MaiaModelStore = .shared) -> BotEngineSelection {
        BotEngineSelection(
            makeMaia: {
                guard let maia else { throw BotEngineError.unavailable("the catalogue lists no network") }
                return try await store.engine(for: maia)
            },
            makeStockfish: { try await StockfishBotEngine.start() }
        )
    }
}
