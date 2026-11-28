import ChessCore
import Foundation

/// A short, fixed set of positions, each resolved before the next: find the
/// move, or ask to be shown it and then play it. Ported from the site's
/// `components/habit/position-trainer.tsx`, which the Daily 5 uses:
///
/// - only the expected move is right (no engine second opinion, as on the site);
/// - a wrong move is refused and the player looks again;
/// - "Show me" draws the move, which the player still plays on the board;
/// - the result of a position is `solved` (first try, no help), `missed` (a
///   wrong move first) or `revealed` (shown), known when the move is played.
nonisolated struct PositionDrill: Hashable, Sendable {
    enum Feedback: Hashable, Sendable { case idle, wrong, correct, revealed }

    enum Outcome: Equatable, Sendable {
        /// Not a legal move, or the position is already resolved: nothing changes.
        case ignored
        /// A legal move that is not the one: tried again.
        case wrong
        /// The move: the position is resolved with this result.
        case resolved(MistakeResult)
    }

    let items: [TrainItem]
    private(set) var index = 0
    private(set) var feedback = Feedback.idle
    private(set) var missed = false
    private(set) var revealed = false
    /// Positions solved at the first try, without help.
    private(set) var solvedFirstTry = 0
    private(set) var results: [MistakeResult] = []

    init(items: [TrainItem]) {
        self.items = items
    }

    var item: TrainItem? { items.indices.contains(index) ? items[index] : nil }
    var isLast: Bool { index >= items.count - 1 }
    /// Every position resolved.
    var isComplete: Bool { results.count == items.count && !items.isEmpty }
    /// Positions resolved, for the progress line.
    var done: Int { results.count }

    var start: Position? { item.flatMap { Position(fen: $0.fen) } }

    var expected: Move? {
        guard let item, let start, let move = Move(uci: item.bestUci) else { return nil }
        return start.normalized(move)
    }

    mutating func play(_ move: Move) -> Outcome {
        guard feedback != .correct, let start, let expected, start.playing(move) != nil else { return .ignored }
        guard start.normalized(move) == expected else {
            missed = true
            feedback = .wrong
            return .wrong
        }
        feedback = .correct
        let result: MistakeResult = revealed ? .revealed : missed ? .missed : .solved
        if result == .solved { solvedFirstTry += 1 }
        results.append(result)
        return .resolved(result)
    }

    mutating func reveal() {
        guard feedback != .correct, item != nil else { return }
        revealed = true
        feedback = .revealed
    }

    /// The next position, once this one is resolved.
    mutating func next() {
        guard feedback == .correct, !isLast else { return }
        index += 1
        feedback = .idle
        missed = false
        revealed = false
    }
}
