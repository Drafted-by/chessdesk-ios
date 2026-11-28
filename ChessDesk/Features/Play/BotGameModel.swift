import ChessCore
import Foundation
import Observation

/// One game against a bot, on screen: it asks the engine for the bot's
/// moves, keeps the game on the device after every move, and saves it to the
/// account when it is over. The flow of the site's `use-bot-game.ts` and of
/// `ActiveGame` in `play-app.tsx`.
@Observable
final class BotGameModel {
    /// What became of the finished game.
    enum Saving: Equatable {
        /// Still playing, or nothing was asked yet.
        case idle
        case saving
        /// In the account: its id opens the review.
        case saved(gameID: String)
        /// Kept on this device until the player has an account.
        case waitingForAccount
        case failed(String)
        /// This backend keeps no bot games: nothing is promised.
        case unavailable
    }

    private(set) var game: BotGame
    private(set) var saving = Saving.idle
    /// Called after every move, with whether it captured: the board's sound.
    var onMovePlayed: (Bool) -> Void = { _ in }

    let engine: any BotEngine
    var engineKind: BotEngineKind { engine.kind }

    private let app: AppModel
    private let store: BotGameStore?
    /// If the engine never answers, a random legal move is played rather
    /// than leaving the game on "thinking": the catalogue's `moveTimeoutMs`.
    private let moveTimeout: Duration
    /// The least time before the bot answers, so its move does not land on
    /// top of the player's own.
    private let replyFloor: Duration
    private var request: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(
        game: BotGame,
        engine: any BotEngine,
        app: AppModel,
        store: BotGameStore? = .standard,
        moveTimeout: Duration,
        replyFloor: Duration = .milliseconds(350)
    ) {
        self.game = game
        self.engine = engine
        self.app = app
        self.store = store
        self.moveTimeout = moveTimeout
        self.replyFloor = replyFloor
        keep()
    }

    var thinking: Bool { game.botToMove }
    var humanName: String { app.me?.user.name.isEmpty == false ? app.me?.user.name ?? "You" : "You" }
    var pgn: String { game.pgn(humanName: humanName) }

    // MARK: Playing

    /// The screen is showing: the bot moves if it is its turn.
    func begin() {
        askBot()
    }

    /// The screen went away: the game waits on the device.
    func pause() {
        request?.cancel()
        request = nil
    }

    /// The player's move; false when it was refused.
    @discardableResult
    func play(_ move: Move) -> Bool {
        let capture = game.position.isCapture(game.position.normalized(move))
        guard game.playHuman(move) != nil else { return false }
        moved(capture: capture)
        return true
    }

    func resign() {
        guard !game.isOver else { return }
        // A reply still on its way is dropped.
        request?.cancel()
        request = nil
        game.resign()
        keep()
        finish()
    }

    /// The same bot and settings again, on the other side if asked.
    func rematch(swappingSides: Bool) {
        guard game.isOver else { return }
        var setup = game.setup
        if swappingSides { setup.humanSide = setup.humanSide.opposite }
        guard let next = BotGame(setup: setup) else { return }
        saveTask?.cancel()
        saveTask = nil
        game = next
        saving = .idle
        keep()
        askBot()
    }

    private func moved(capture: Bool) {
        onMovePlayed(capture)
        keep()
        if game.isOver { finish() } else { askBot() }
    }

    private func askBot() {
        guard game.botToMove, request == nil else { return }
        let fen = game.position.fen
        let setup = game.setup
        let signature = game.signatureMove?.uci
        let engine = engine
        let timeout = moveTimeout
        let floor = replyFloor
        request = Task { [weak self] in
            let started = ContinuousClock.now
            var answer = signature
            if answer == nil {
                answer = try? await withDeadline(timeout) {
                    try await engine.bestMove(fen: fen, strength: setup.strength)
                }
            }
            let spent = ContinuousClock.now - started
            if spent < floor { try? await Task.sleep(for: floor - spent) }
            guard !Task.isCancelled else { return }
            self?.settle(answer, for: fen)
        }
    }

    /// Applies the engine's answer, if the world has not moved on meanwhile.
    private func settle(_ answer: String?, for fen: String) {
        request = nil
        guard game.botToMove, game.position.fen == fen else { return }
        let before = game.position
        guard let played = game.playBot(answer: answer) else { return }
        moved(capture: before.isCapture(played.move))
    }

    /// Writes the game to the device; a finished game leaves the slot.
    private func keep() {
        store?.setCurrent(game.isOver ? nil : BotGameSnapshot(game, engine: engine.kind))
    }

    // MARK: Saving

    /// The game is over: a signed-in player's game is saved at once, so "saved
    /// to your games" is true whatever they tap next; a guest's waits on the
    /// device for an account.
    private func finish() {
        guard game.isOver, saving == .idle else { return }
        guard app.api.savesBotGames else {
            saving = .unavailable
            return
        }
        if app.token != nil, app.isSignedIn {
            save()
        } else {
            store?.setPending(PendingBotGame(request: game.saveRequest(humanName: "You", engine: engine.kind)))
            saving = .waitingForAccount
        }
    }

    /// The account changed while the result was on screen: a guest who has
    /// just signed in gets the game saved.
    func accountChanged() {
        if saving == .waitingForAccount, app.isSignedIn { save() }
    }

    /// Saves the finished game; also the retry after a failure.
    func save() {
        guard game.isOver, saveTask == nil, let token = app.token else { return }
        if case .saved = saving { return }
        saving = .saving
        let request = game.saveRequest(humanName: humanName, engine: engine.kind)
        let api = app.api
        saveTask = Task { [weak self] in
            let outcome: Saving
            var unreachable = false
            do {
                outcome = .saved(gameID: try await api.saveBotGame(request, token: token).id)
            } catch let error as APIError {
                outcome = .failed(error.message)
                unreachable = error == .offline
            } catch {
                outcome = .failed(APIError.unreadable.message)
            }
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.saving = outcome
            if case .saved = outcome {
                self.store?.setPending(nil)
            } else if unreachable {
                // Finished without a connection: the game waits on the device
                // and is saved the next time the bots are opened.
                self.store?.setPending(PendingBotGame(request: request))
            }
        }
    }

    /// For tests: waits until the pending save has answered.
    func waitForSave() async {
        await saveTask?.value
    }
}
