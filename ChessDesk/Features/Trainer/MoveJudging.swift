import Foundation

/// A question for the engine about a move that is not the course's.
nonisolated enum JudgeQuestion: Sendable, Equatable {
    /// No engine needed: the move is right (it mates on the spot).
    case accepted
    /// Does the learner still mate within this many more moves of theirs?
    case mate(fenAfterPlayed: String, within: Int)
    /// Is the move as good as the course's move?
    case equal(fenAfterPlayed: String, fenAfterExpected: String)
}

/// Decides whether a different move is as good as the course's. The app's
/// implementation is Stockfish on the device (`EngineJudge`).
nonisolated protocol MoveJudging: Sendable {
    func accepts(_ question: JudgeQuestion) async -> Bool
}
