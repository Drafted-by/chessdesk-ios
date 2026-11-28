import ChessCore
import StockfishEngine
import SwiftUI

#if DEBUG
    /// Launch arguments for checking the feature in the simulator:
    /// `-CDRoute play` opens the Play tab, `-CDRoute play/<bot id>` starts a game
    /// against that bot (`play/custom` with `-CDPlayRating 1500`, `play/resume`
    /// for the game in progress), `-CDPlaySide black` takes Black.
    /// `-CDPlayAutopilot engine|random` plays the player's moves, so a whole
    /// game runs unattended: `engine` asks Stockfish at full strength,
    /// `random` picks any legal move. `-CDPlayAutopilotMoves 6` stops after
    /// six of them; `-CDPlayAutopilotResign YES` then resigns.
    enum PlayDebug {
        /// The route is acted on once per launch.
        static var consumed = false

        static var customRating: Int? {
            let rating = UserDefaults.standard.integer(forKey: "CDPlayRating")
            return rating > 0 ? rating : nil
        }

        private static var running: Task<Void, Never>?

        static func autopilot(_ model: BotGameModel) {
            guard let mode = UserDefaults.standard.string(forKey: "CDPlayAutopilot") else { return }
            let limit = UserDefaults.standard.integer(forKey: "CDPlayAutopilotMoves")
            let resigns = UserDefaults.standard.bool(forKey: "CDPlayAutopilotResign")
            running?.cancel()
            running = Task {
                var played = 0
                while !Task.isCancelled, !model.game.isOver {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard model.game.humanToMove else { continue }
                    if limit > 0, played >= limit {
                        if resigns { model.resign() }
                        return
                    }
                    let position = model.game.position
                    var move = position.legalMoves().randomElement()
                    if mode == "engine", let network = DeviceEngine.networkURL {
                        try? await StockfishEngine.shared.start(network: network)
                        let best = try? await StockfishEngine.shared.evaluate(fen: position.fen, depth: 10, maxTime: .milliseconds(400))
                        if let uci = best?.bestMove, let found = Move(uci: uci) { move = found }
                    }
                    guard let move, model.game.humanToMove, model.game.position == position else { continue }
                    if model.play(move) { played += 1 }
                }
            }
        }
    }
#endif
