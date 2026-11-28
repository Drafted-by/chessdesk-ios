import ChessCore
import Foundation
import Observation
import StockfishEngine

/// Something that searches a position until told to stop: Stockfish on the
/// device, a stub in tests. Ending the stream stops the search.
nonisolated protocol LiveAnalysing: Sendable {
    func analyse(fen: String, lines: Int) -> AsyncThrowingStream<LiveSearchUpdate, Error>
}

/// Stockfish on the device, deepening while the position stays on screen.
nonisolated struct DeviceLiveAnalysis: LiveAnalysing {
    /// Deeper than the site's analysis board (depth 20): a phone gets there in
    /// tens of seconds, and stopping there spares the battery.
    static let maxDepth = 24

    func analyse(fen: String, lines: Int) -> AsyncThrowingStream<LiveSearchUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let network = DeviceEngine.networkURL else {
                        throw EngineError.networkMissing(StockfishEngine.networkName)
                    }
                    try await StockfishEngine.shared.start(network: network)
                    for try await update in StockfishEngine.shared.liveSearch(fen: fen, lines: lines, maxDepth: Self.maxDepth) {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// One engine line as the analysis board shows it: White's point of view,
/// in SAN, as the site's engine panel (`components/study/use-engine.ts`).
nonisolated struct EngineLine: Identifiable, Hashable, Sendable {
    /// 1 for the best line.
    let id: Int
    /// Centipawns for White; nil when the score is a mate.
    let whiteCentipawns: Int?
    /// Moves to mate: positive when White mates.
    let whiteMate: Int?
    let depth: Int
    let moves: [Move]
    let san: [String]

    init(id: Int, evaluation: EngineEvaluation, position: Position) {
        self.id = id
        let sign = position.turn == .white ? 1 : -1
        whiteCentipawns = evaluation.centipawns.map { $0 * sign }
        whiteMate = evaluation.mate.map { $0 * sign }
        depth = evaluation.depth
        san = position.sanLine(uci: evaluation.principalVariation)
        moves = evaluation.principalVariation.prefix(san.count).compactMap { Move(uci: $0) }
    }

    /// "+0.31", "-1.20", "0.00", "#3", "#-2" (`formatScore`).
    var scoreText: String {
        EngineScore.text(whiteCentipawns: whiteCentipawns, whiteMate: whiteMate)
    }

    /// The score as printed, with a true minus sign.
    var displayScore: String { scoreText.replacingOccurrences(of: "-", with: "−") }

    /// The side the score favours, for the chip colour (`scoreTone`).
    var tone: EngineScore.Tone { EngineScore.tone(whiteCentipawns: whiteCentipawns, whiteMate: whiteMate) }
}

/// The site's arithmetic for engine scores and the evaluation bar
/// (`components/review/eval-bar.tsx`, `engine-panel.tsx`, `use-engine.ts`).
nonisolated enum EngineScore {
    enum Tone: Hashable, Sendable { case white, black, even }

    static func text(whiteCentipawns: Int?, whiteMate: Int?) -> String {
        if let mate = whiteMate { return "#\(mate < 0 ? "-" : "")\(abs(mate))" }
        guard let cp = whiteCentipawns else { return "" }
        let pawns = (Double(cp) / 100).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
        return cp > 0 ? "+\(pawns)" : pawns
    }

    static func tone(whiteCentipawns: Int?, whiteMate: Int?) -> Tone {
        let value = whiteMate ?? whiteCentipawns ?? 0
        return value == 0 ? .even : value > 0 ? .white : .black
    }

    /// White's share of the bar, 0…100: a mate fills it, a score moves it
    /// 7 points a pawn from the middle, between 3 and 97 (`evalBarWhitePct`).
    static func whiteShare(whiteCentipawns: Int?, whiteMate: Int?) -> Double {
        if let mate = whiteMate { return mate > 0 ? 100 : 0 }
        guard let cp = whiteCentipawns else { return 50 }
        return max(3, min(97, 50 + Double(cp) / 100 * 7))
    }
}

/// The engine half of the analysis board: shows the best lines of whatever
/// position it is given, deepening until the position changes. A new
/// position ends the previous search before the next one starts, so the
/// shared engine is never asked twice at once.
@Observable
final class LiveAnalysisModel {
    enum Status: Equatable {
        case off
        case searching
        /// The search reached its depth, or the position has no moves.
        case done
        case unavailable(String)
    }

    private(set) var lines: [EngineLine] = []
    private(set) var depth = 0
    private(set) var status: Status = .off
    /// The position the lines are about.
    private(set) var position: Position?

    var isOn = true {
        didSet {
            guard isOn != oldValue else { return }
            if let position { restart(position) }
        }
    }

    let lineCount: Int
    @ObservationIgnored private let engine: any LiveAnalysing
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(engine: any LiveAnalysing = DeviceLiveAnalysis(), lineCount: Int = 3) {
        self.engine = engine
        self.lineCount = lineCount
    }

    var best: EngineLine? { lines.first }

    /// Analyses `position` from now on. The same position again changes nothing.
    func show(_ position: Position) {
        guard position != self.position else { return }
        self.position = position
        restart(position)
    }

    /// Searches the last position again after `stop()`: the screen is back.
    func resume() {
        guard task == nil, let position else { return }
        restart(position)
    }

    /// Ends the search: the screen went away.
    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        if case .searching = status { status = isOn ? .done : .off }
    }

    private func restart(_ position: Position) {
        generation += 1
        let current = generation
        task?.cancel()
        task = nil
        lines = []
        depth = 0
        guard isOn else {
            status = .off
            return
        }
        // A finished or impossible position is not given to the engine.
        guard position.setupProblem == nil, position.outcome == nil || position.outcome == .fiftyMoveRule else {
            status = .done
            return
        }
        status = .searching
        let stream = engine.analyse(fen: position.fen, lines: lineCount)
        task = Task { [weak self] in
            do {
                for try await update in stream {
                    guard let self, self.generation == current else { return }
                    self.depth = update.depth
                    self.lines = update.lines.enumerated().map {
                        EngineLine(id: $0.offset + 1, evaluation: $0.element, position: position)
                    }
                }
                guard let self, self.generation == current else { return }
                self.status = .done
            } catch {
                guard let self, self.generation == current, !(error is CancellationError) else { return }
                self.status = .unavailable("The engine could not start on this device.")
            }
        }
    }
}
