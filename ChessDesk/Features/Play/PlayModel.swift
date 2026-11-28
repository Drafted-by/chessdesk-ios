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
        case .custom: BotGameSetup.customBotID
        }
    }

    /// What a game against this opponent is set up with. A character brings
    /// its opening move and its wildness; a built opponent has neither.
    func setup(rating: Int, humanSide: Side, start: BotStart) -> BotGameSetup {
        switch self {
        case let .bot(bot):
            BotGameSetup(
                botID: bot.id, botName: bot.name, rating: bot.rating, avatar: bot.avatar, country: bot.country,
                humanSide: humanSide, firstMove: bot.firstMove, wildness: bot.wildness, start: start
            )
        case let .custom(custom):
            BotGameSetup(
                botID: BotGameSetup.customBotID, botName: custom.name, rating: rating, avatar: custom.avatar, country: nil,
                humanSide: humanSide, firstMove: nil, wildness: custom.wildness, start: start
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
    /// The game waiting on this device, if any.
    private(set) var resumable: BotGameSnapshot?
    /// True while the opponent's engine loads.
    private(set) var isStarting = false
    private(set) var startFailure: String?
    /// A guest's game that has just been saved to their new account.
    private(set) var claimedGameID: String?

    private let app: AppModel
    private let store: BotGameStore
    private let engines: @Sendable (MaiaModelInfo?) -> BotEngineSelection

    init(
        app: AppModel,
        store: BotGameStore = .standard,
        engines: @escaping @Sendable (MaiaModelInfo?) -> BotEngineSelection = PlayModel.deviceEngines
    ) {
        self.app = app
        self.store = store
        self.engines = engines
    }

    /// Maia from the catalogue's network, Stockfish from the app bundle.
    /// `-CDPlayEngine stockfish` (Debug) leaves Maia out, to check the fallback.
    nonisolated static let deviceEngines: @Sendable (MaiaModelInfo?) -> BotEngineSelection = { maia in
        #if DEBUG
            if UserDefaults.standard.string(forKey: "CDPlayEngine") == "stockfish" { return .device(maia: nil) }
        #endif
        return .device(maia: maia)
    }

    var catalogue: PlayCatalogue? {
        if case let .ready(catalogue) = phase { return catalogue }
        return nil
    }

    func load() async {
        refresh()
        do {
            phase = .ready(try await app.api.playBots(token: app.token))
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(APIError.unreadable.message)
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
        guard !isStarting else { return nil }
        isStarting = true
        startFailure = nil
        defer { isStarting = false }
        do {
            let engine = try await engines(catalogue?.maia).make()
            let model = BotGameModel(game: game, engine: engine, app: app, store: store)
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
        claimedGameID = saved.gameId
    }

    func claimedGameShown() {
        claimedGameID = nil
    }
}
