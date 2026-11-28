import Foundation

/// One report of a live search: the best lines found so far, best first.
public struct LiveSearchUpdate: Sendable, Equatable {
    /// The depth of the best line.
    public let depth: Int
    public let lines: [EngineEvaluation]

    public init(depth: Int, lines: [EngineEvaluation]) {
        self.depth = depth
        self.lines = lines
    }
}

/// What an analysis board needs on top of the one-shot searches: a search
/// that deepens until it is told to stop, reporting each depth as it goes.
extension StockfishEngine {
    /// Searches `fen` for its best `lines` lines, deepening until the stream
    /// ends (or to `maxDepth` when one is given), and reports each completed
    /// depth. Ending the stream, by cancelling the task that reads it, stops
    /// the engine at once and frees it for the next search. Like the other
    /// searches, it waits for the engine when another search is running.
    public nonisolated func liveSearch(
        fen: String,
        lines: Int = 3,
        maxDepth: Int? = nil
    ) -> AsyncThrowingStream<LiveSearchUpdate, Error> {
        let token = LiveSearchToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                Task { await self.endLiveSearch(token) }
            }
            Task {
                await self.runLiveSearch(fen: fen, lines: lines, maxDepth: maxDepth, token: token, continuation: continuation)
            }
        }
    }

    /// Asks the running search, whatever it is, to stop now: a one-shot
    /// search then returns what it has found so far.
    public func stopSearch() {
        guard isReady else { return }
        send("stop")
    }

    private func runLiveSearch(
        fen: String,
        lines: Int,
        maxDepth: Int?,
        token: LiveSearchToken,
        continuation: AsyncThrowingStream<LiveSearchUpdate, Error>.Continuation
    ) async {
        guard isReady else {
            continuation.finish(throwing: EngineError.notStarted)
            return
        }
        await acquire()
        defer { release() }
        // Ended while it waited for the engine: never started.
        guard !token.isEnded else {
            continuation.finish()
            return
        }
        token.isRunning = true
        send("setoption name MultiPV value \(max(1, lines))")
        send("position fen \(fen)")
        send(maxDepth.map { "go depth \(max(1, $0))" } ?? "go infinite")

        // The engine prints every line of a depth in a row (multipv 1, 2, 3):
        // a report goes out when the last of them arrives.
        var latest: [Int: EngineEvaluation] = [:]
        var widest = 0
        while true {
            let line = await mailbox.next()
            if line.hasPrefix("bestmove") { break }
            guard let parsed = Self.parseInfo(line), !parsed.principalVariation.isEmpty else { continue }
            let index = Self.lineIndex(line)
            latest[index] = parsed
            widest = max(widest, index)
            guard index == widest, !token.isEnded else { continue }
            let sorted = latest.keys.sorted().compactMap { latest[$0] }
            continuation.yield(LiveSearchUpdate(depth: latest[1]?.depth ?? parsed.depth, lines: sorted))
        }
        token.isRunning = false
        send("setoption name MultiPV value 1")
        continuation.finish()
    }

    private func endLiveSearch(_ token: LiveSearchToken) {
        token.isEnded = true
        if token.isRunning { send("stop") }
    }
}

/// The state of one live search, read and written on the engine actor only.
final class LiveSearchToken: @unchecked Sendable {
    var isEnded = false
    var isRunning = false
}
