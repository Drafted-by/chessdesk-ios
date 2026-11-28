import CStockfish
import Foundation

/// What the engine thinks of a position, from the side to move.
public struct EngineEvaluation: Sendable, Equatable {
    /// Centipawns; nil when the score is a forced mate.
    public let centipawns: Int?
    /// Moves to mate: positive when the side to move mates, negative when it is mated.
    public let mate: Int?
    public let depth: Int
    /// The engine's line, in UCI moves. Empty when there is no legal move.
    public let principalVariation: [String]

    public init(centipawns: Int?, mate: Int?, depth: Int, principalVariation: [String]) {
        self.centipawns = centipawns
        self.mate = mate
        self.depth = depth
        self.principalVariation = principalVariation
    }

    public var bestMove: String? { principalVariation.first }

    /// One number to compare two moves: a mate counts as ±10,000 minus its distance.
    public var comparable: Int {
        if let mate { return mate > 0 ? 10_000 - mate : -10_000 - mate }
        return centipawns ?? 0
    }
}

public enum EngineError: Error, Equatable {
    case networkMissing(String)
    case notStarted
}

/// Stockfish, running inside the app. One engine per process, one search at a
/// time: calls queue up and are answered in order.
public actor StockfishEngine {
    public static let shared = StockfishEngine()

    /// The network file this build of the engine expects.
    public static let networkName = "nn-1a298aa575a0.nnue"

    let mailbox = LineMailbox.shared
    private(set) var isReady = false
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Starts the engine and loads its network. Safe to call more than once.
    public func start(network: URL) async throws {
        guard !isReady else { return }
        guard FileManager.default.fileExists(atPath: network.path) else {
            throw EngineError.networkMissing(network.lastPathComponent)
        }
        await acquire()
        defer { release() }
        guard !isReady else { return }
        sf_start({ line, _ in
            guard let line else { return }
            LineMailbox.shared.push(String(cString: line))
        }, nil)
        send("uci")
        await wait(for: "uciok")
        send("setoption name Threads value 1")
        send("setoption name Hash value 16")
        send("setoption name EvalFile value \(network.path)")
        send("isready")
        await wait(for: "readyok")
        isReady = true
    }

    /// Searches a position to `depth`, for at most `maxTime`.
    public func evaluate(
        fen: String,
        depth: Int = 12,
        maxTime: Duration = .milliseconds(1200)
    ) async throws -> EngineEvaluation {
        guard isReady else { throw EngineError.notStarted }
        await acquire()
        defer { release() }
        let parts = maxTime.components
        let milliseconds = max(50, Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000))
        send("position fen \(fen)")
        send("go depth \(depth) movetime \(milliseconds)")
        var latest = EngineEvaluation(centipawns: 0, mate: nil, depth: 0, principalVariation: [])
        while true {
            let line = await mailbox.next()
            if line.hasPrefix("bestmove") { return latest }
            if let parsed = Self.parseInfo(line) { latest = parsed }
        }
    }

    /// Searches a position and returns its best lines, best first: what a
    /// game review needs (the runner-up tells an "only move" from a choice).
    /// A position with one legal move has one line; a finished one has none.
    public func analyse(
        fen: String,
        depth: Int,
        maxTime: Duration,
        lines: Int = 2
    ) async throws -> [EngineEvaluation] {
        guard isReady else { throw EngineError.notStarted }
        await acquire()
        defer { release() }
        let parts = maxTime.components
        let milliseconds = max(50, Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000))
        send("setoption name MultiPV value \(max(1, lines))")
        send("position fen \(fen)")
        send("go depth \(depth) movetime \(milliseconds)")
        var latest: [Int: EngineEvaluation] = [:]
        while true {
            let line = await mailbox.next()
            if line.hasPrefix("bestmove") { break }
            if let parsed = Self.parseInfo(line), !parsed.principalVariation.isEmpty {
                latest[Self.lineIndex(line)] = parsed
            }
        }
        send("setoption name MultiPV value 1")
        return latest.keys.sorted().compactMap { latest[$0] }
    }

    /// More threads and memory for a game review, back to one for the trainer.
    public func configure(threads: Int, hashMegabytes: Int) async {
        guard isReady else { return }
        await acquire()
        defer { release() }
        send("setoption name Threads value \(max(1, threads))")
        send("setoption name Hash value \(max(16, hashMegabytes))")
        send("isready")
        await wait(for: "readyok")
    }

    /// The "multipv 2" of an info line; 1 when the engine prints a single line.
    static func lineIndex(_ line: String) -> Int {
        let tokens = line.split(separator: " ")
        guard let index = tokens.firstIndex(of: "multipv"), index + 1 < tokens.count else { return 1 }
        return Int(tokens[index + 1]) ?? 1
    }

    /// Reads one "info … score cp 31 … pv e2e4 e7e5" line. Lines without a
    /// score (currmove, strings) and bounds are skipped.
    static func parseInfo(_ line: String) -> EngineEvaluation? {
        guard line.hasPrefix("info ") else { return nil }
        let tokens = line.split(separator: " ")
        guard let scoreIndex = tokens.firstIndex(of: "score"), scoreIndex + 2 < tokens.count,
              let value = Int(tokens[scoreIndex + 2])
        else { return nil }
        // A bound is not the score: wait for the exact one.
        if tokens.contains("lowerbound") || tokens.contains("upperbound") { return nil }
        let kind = tokens[scoreIndex + 1]
        guard kind == "cp" || kind == "mate" else { return nil }
        let depth = tokens.firstIndex(of: "depth").flatMap { $0 + 1 < tokens.count ? Int(tokens[$0 + 1]) : nil } ?? 0
        let moves = tokens.firstIndex(of: "pv").map { tokens[($0 + 1)...].map(String.init) } ?? []
        return EngineEvaluation(
            centipawns: kind == "cp" ? value : nil,
            mate: kind == "mate" ? value : nil,
            depth: depth,
            principalVariation: moves
        )
    }

    // MARK: Plumbing

    func send(_ command: String) {
        command.withCString { sf_send($0) }
    }

    private func wait(for answer: String) async {
        while await mailbox.next() != answer {}
    }

    func acquire() async {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Lines printed by the engine, handed from its threads to the one reader.
final class LineMailbox: @unchecked Sendable {
    static let shared = LineMailbox()

    private let lock = NSLock()
    private var lines: [String] = []
    private var reader: CheckedContinuation<String, Never>?

    func push(_ line: String) {
        let waiting: CheckedContinuation<String, Never>? = lock.withLock {
            if let reader {
                self.reader = nil
                return reader
            }
            lines.append(line)
            return nil
        }
        waiting?.resume(returning: line)
    }

    func next() async -> String {
        await withCheckedContinuation { continuation in
            let ready: String? = lock.withLock {
                if lines.isEmpty {
                    reader = continuation
                    return nil
                }
                return lines.removeFirst()
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
