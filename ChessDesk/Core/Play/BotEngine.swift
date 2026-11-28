import Foundation

/// The engine that really played a game: saved with it, so a game is never
/// labelled with an engine it did not meet. Raw values are the site's.
nonisolated enum BotEngineKind: String, Codable, Hashable, Sendable {
    case maia = "maia-3"
    case stockfish
}

nonisolated enum BotEngineError: Error, Equatable {
    case timedOut
    case noMove
    case unavailable(String)
}

/// Where a bot's move comes from. Everything above this protocol ignores
/// whether Maia or Stockfish answered, except `kind`. A port of the site's
/// `lib/play/engine/bot-engine.ts`.
nonisolated protocol BotEngine: Sendable {
    var kind: BotEngineKind { get }
    /// A move in UCI ("e2e4", "e7e8q") for the side to move in `fen`, played
    /// at `strength`.
    func bestMove(fen: String, strength: BotStrength) async throws -> String
}

/// How strongly a bot plays, as the catalogue states it. Each engine reads
/// what concerns it.
nonisolated struct BotStrength: Codable, Hashable, Sendable {
    /// The rating Maia plays at.
    var rating: Int
    /// How loosely Maia samples; nil leaves the catalogue's default.
    var temperature: Double?
    /// The `UCI_Elo` Stockfish is held to.
    var stockfishElo: Int

    /// The warm-up move the site asks of Maia before trusting it with a game
    /// (the start position at 1500: `docs/api/README.md`, "Which engine").
    static let warmup = BotStrength(rating: 1500, temperature: nil, stockfishElo: 1500)
}

/// Runs `work`, but gives up after `duration`: the caller gets `timedOut` and
/// goes on, the work is cancelled and left to finish on its own.
nonisolated func withDeadline<Value: Sendable>(
    _ duration: Duration,
    _ work: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let race = DeadlineRace<Value>()
    return try await withCheckedThrowingContinuation { continuation in
        race.start(continuation)
        let worker = Task {
            do {
                race.finish(.success(try await work()))
            } catch {
                race.finish(.failure(error))
            }
        }
        Task {
            try? await Task.sleep(for: duration)
            if race.finish(.failure(BotEngineError.timedOut)) { worker.cancel() }
        }
    }
}

/// The first of two answers wins; the other is dropped.
private nonisolated final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    func start(_ continuation: CheckedContinuation<Value, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    @discardableResult
    func finish(_ result: Result<Value, Error>) -> Bool {
        let waiting = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
        return waiting != nil
    }
}

/// Picks the engine of a game, as the site does (`lib/play/engine/select.ts`):
/// the engines are tried in the catalogue's order. Maia plays when it loads
/// and answers a first move within its two budgets; otherwise Stockfish, held
/// to a rating, plays the whole game. A game always gets an engine that works.
nonisolated struct BotEngineSelection: Sendable {
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// The catalogue's `engines.order`.
    var order: [BotEngineKind] = [.maia, .stockfish]
    /// Loads Maia (the network may have to be downloaded first).
    var makeMaia: @Sendable () async throws -> any BotEngine
    var makeStockfish: @Sendable () async throws -> any BotEngine
    /// The catalogue's `maia.initBudgetMs` and `maia.warmupBudgetMs`.
    var loadBudget: Duration
    var warmupBudget: Duration

    func make() async throws -> any BotEngine {
        var failure: any Error = BotEngineError.unavailable("the catalogue lists no engine this app runs")
        for kind in order {
            do {
                switch kind {
                case .maia:
                    let makeMaia = makeMaia
                    let maia = try await withDeadline(loadBudget) { try await makeMaia() }
                    _ = try await withDeadline(warmupBudget) {
                        try await maia.bestMove(fen: Self.startFEN, strength: .warmup)
                    }
                    return maia
                case .stockfish:
                    return try await makeStockfish()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // This engine could not load or is too slow here: the next one plays.
                failure = error
            }
        }
        throw failure
    }
}
