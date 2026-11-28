import ChessCore
import Foundation
import Observation

/// The side a player asks for before a game.
nonisolated enum SideChoice: String, CaseIterable, Hashable, Sendable {
    case white, black, random

    var label: String {
        switch self {
        case .white: "White"
        case .black: "Black"
        case .random: "Random"
        }
    }

    func resolved(coin: () -> Bool = { Bool.random() }) -> Side {
        switch self {
        case .white: .white
        case .black: .black
        case .random: coin() ? .white : .black
        }
    }
}

/// The opponent picked in the catalogue: a character, or a rating of one's own.
nonisolated enum OpponentPick: Hashable, Identifiable, Sendable {
    case bot(PlayBot)
    case custom(CustomOpponent)

    var id: String {
        switch self {
        case let .bot(bot): bot.id
        case let .custom(custom): custom.id
        }
    }

    var access: BotAccess {
        switch self {
        case let .bot(bot): bot.access
        case let .custom(custom): custom.access
        }
    }

    /// What a game against this opponent is set up with, every number from
    /// the catalogue. A character brings its rating, its opening move, its
    /// temperature and its Stockfish Elo. A built opponent plays at the
    /// rating asked (held to its range), with the custom temperature, no
    /// opening move, and that rating held to what Stockfish accepts.
    func setup(rating: Int, humanSide: Side, start: BotStart, engines: PlayEngines) -> BotGameSetup {
        switch self {
        case let .bot(bot):
            return BotGameSetup(
                botID: bot.id, botName: bot.name, rating: bot.rating, avatar: bot.portraitUrl, country: bot.country,
                humanSide: humanSide, firstMove: bot.firstMove, temperature: bot.temperature,
                stockfishElo: bot.stockfishElo, start: start
            )
        case let .custom(custom):
            let rating = max(custom.rating.min, min(max(custom.rating.min, custom.rating.max), rating))
            return BotGameSetup(
                botID: custom.id, botName: custom.name, rating: rating, avatar: custom.portraitUrl, country: nil,
                humanSide: humanSide, firstMove: nil, temperature: custom.temperature,
                stockfishElo: engines.stockfish.elo(forRating: rating), isCustom: true, start: start
            )
        }
    }
}

/// The play hub: the catalogue, the game in progress, and starting a game
/// (which loads the bot's engine first).
@Observable
final class PlayModel {
    enum Phase: Equatable {
        case loading
        case ready(PlayCatalogue)
        case failed(String)
    }

    private(set) var phase = Phase.loading
    /// True when the catalogue on screen is the one kept from an earlier
    /// visit, because the server could not be reached this time.
    private(set) var isFromCache = false
    /// The game waiting on this device, if any.
    private(set) var resumable: BotGameSnapshot?
    /// True while the opponent's engine loads.
    private(set) var isStarting = false
    private(set) var startFailure: String?
    /// A guest's game that has just been saved to their new account.
    private(set) var claimedGameID: String?

    private let app: AppModel
    private let store: BotGameStore
    private let cache: PlayCatalogueCache?
    private let engines: @Sendable (PlayEngines) -> BotEngineSelection

    init(
        app: AppModel,
        store: BotGameStore = .standard,
        cache: PlayCatalogueCache? = .standard,
        engines: @escaping @Sendable (PlayEngines) -> BotEngineSelection = PlayModel.deviceEngines
    ) {
        self.app = app
        self.store = store
        self.cache = cache
        self.engines = engines
    }

    /// The engines as the catalogue sets them up: Maia from the network it
    /// names, Stockfish from the app bundle. `-CDPlayEngine stockfish`
    /// (Debug) leaves Maia out, to check the fallback.
    nonisolated static let deviceEngines: @Sendable (PlayEngines) -> BotEngineSelection = { engines in
        #if DEBUG
            if UserDefaults.standard.string(forKey: "CDPlayEngine") == "stockfish" { return .device(engines, maia: false) }
        #endif
        return .device(engines)
    }

    var catalogue: PlayCatalogue? {
        if case let .ready(catalogue) = phase { return catalogue }
        return nil
    }

    /// Asks the server for the catalogue and keeps its answer on the device.
    /// The catalogue kept from the last visit shows at once, and stays when
    /// the server cannot be reached: a player without a connection still
    /// finds the bots. Only a device that never loaded them sees the failure.
    func load() async {
        refresh()
        let backend = app.backend
        let kept = cache?.catalogue(for: backend)
        if catalogue == nil, let kept {
            phase = .ready(kept)
            isFromCache = true
        }
        do {
            let fresh = try await app.api.playBots(token: app.token)
            guard backend == app.backend else { return }
            cache?.keep(fresh, for: backend)
            phase = .ready(fresh)
            isFromCache = false
        } catch is CancellationError {
        } catch {
            guard backend == app.backend else { return }
            if let shown = catalogue ?? kept {
                phase = .ready(shown)
                isFromCache = true
            } else {
                phase = .failed((error as? APIError)?.message ?? APIError.unreadable.message)
            }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// Reads the game in progress again: after a game screen closes.
    func refresh() {
        resumable = store.current()
    }

    /// Gives up the game in progress without playing it out.
    func discardResumable() {
        store.setCurrent(nil)
        resumable = nil
    }

    /// Starts a new game: the engine loads, then the game opens. Nil when the
    /// engine could not start; `startFailure` says so.
    func start(_ setup: BotGameSetup) async -> BotGameModel? {
        guard let game = BotGame(setup: setup) else { return nil }
        return await open(game)
    }

    /// Opens the game in progress again, with a freshly loaded engine.
    func resume() async -> BotGameModel? {
        guard let game = store.current()?.restored() else {
            refresh()
            return nil
        }
        return await open(game)
    }

    private func open(_ game: BotGame) async -> BotGameModel? {
        guard !isStarting, let settings = catalogue?.engines else { return nil }
        isStarting = true
        startFailure = nil
        defer { isStarting = false }
        do {
            let engine = try await engines(settings).make()
            let model = BotGameModel(
                game: game, engine: engine, app: app, store: store,
                moveTimeout: .milliseconds(settings.moveTimeoutMs)
            )
            resumable = store.current()
            return model
        } catch {
            startFailure = "The bot could not start. Please try again."
            return nil
        }
    }

    /// A game finished as a guest is saved once the player has an account.
    func claimPendingGame() async {
        guard app.api.savesBotGames, app.isSignedIn, let token = app.token, let pending = store.pending() else { return }
        guard let saved = try? await app.api.saveBotGame(pending.request, token: token) else { return }
        store.setPending(nil)
        claimedGameID = saved.id
    }

    func claimedGameShown() {
        claimedGameID = nil
    }
}
