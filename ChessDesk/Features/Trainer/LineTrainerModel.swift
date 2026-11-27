import ChessCore
import Foundation
import Observation

/// One line of an opening, taught the way the site teaches it
/// (`docs/design.md`, "Opening trainer"):
///
/// 1. **Learn the line.** The whole line from move 1. Each note is shown
///    before its move, with an arrow; the learner plays our moves on the
///    board, the opponent replies by itself. A wrong move is never graded.
/// 2. **Play from memory.** No arrows and no notes unless asked. A miss or a
///    hint grades the move "again", otherwise "good".
@Observable
final class LineTrainerModel {
    enum Phase: Equatable { case guided, play, finished }

    enum Feedback: Equatable {
        /// Guided pass: a gentle retry, the arrow shows the move.
        case notThisOne
        /// Memory pass: a miss.
        case missed
    }

    struct Timing: Sendable {
        var opponentGuided: Duration = .milliseconds(1000)
        var opponentPlay: Duration = .milliseconds(650)
        var firstMove: Duration = .milliseconds(450)
        var wrongHold: Duration = .milliseconds(800)
        var finish: Duration = .milliseconds(600)

        static let immediate = Timing(
            opponentGuided: .zero, opponentPlay: .zero, firstMove: .zero, wrongHold: .zero, finish: .zero
        )
    }

    let line: TrainingLine
    let side: Side
    var timing = Timing()
    /// Called for every move shown on the board: `true` for a capture.
    var onMovePlayed: (Bool) -> Void = { _ in }
    /// Called once when the memory pass ends, with one grade per move of ours.
    var onFinished: ([MoveGrade]) -> Void = { _ in }

    private(set) var phase: Phase = .guided
    /// Index of the next step to be played.
    private(set) var cursor = 0
    private(set) var position: Position
    private(set) var lastMove: Move?
    private(set) var verdict: BoardVerdict?
    private(set) var feedback: Feedback?
    private(set) var hintLevel = 0
    private(set) var noteRevealed = false
    private(set) var isBoardLocked = false
    private(set) var grades: [MoveGrade] = []
    /// Solve: the engine is checking a move that is not the course's.
    private(set) var isJudging = false
    /// Solve: the learner found another move that is as good as the course's.
    private(set) var solvedAnotherWay = false

    private var missed: Set<Int> = []
    private var pending: Task<Void, Never>?
    /// Review: only these steps are graded (the moves that are due). Nil
    /// grades every move of ours, which is what learning a line does.
    private let gradedSteps: Set<Int>?

    /// How the line is worked. Opening courses use `.learn`; a learning path
    /// names `.lesson` (the guided pass is the whole exercise) and `.solve`
    /// (no guided pass: the learner finds the moves).
    let flow: ExerciseFlow
    /// Solve: decides whether a move that is not the course's is as good
    /// (the engine). Nil means only the course's move is accepted.
    var judge: (any MoveJudging)?

    /// - Parameter review: the due steps of a line being reviewed. A review
    ///   starts in the memory pass; there is no guided pass first.
    init(line: TrainingLine, side: Side, review gradedSteps: [Int]? = nil, flow: ExerciseFlow = .learn) {
        self.line = line
        self.side = side
        self.flow = flow
        self.gradedSteps = gradedSteps.map(Set.init)
        position = Position(fen: line.startFen) ?? .start
        if gradedSteps != nil || flow == .solve { phase = .play }
    }

    var isReview: Bool { gradedSteps != nil }

    // MARK: Reading the state

    var steps: [LineStep] { line.steps }
    var currentStep: LineStep? { cursor < steps.count ? steps[cursor] : nil }
    var previousStep: LineStep? { cursor > 0 ? steps[cursor - 1] : nil }
    var isOurTurn: Bool { currentStep?.mine == true && !isBoardLocked }
    var guidedPassDone: Bool { phase == .guided && cursor >= steps.count }
    var ourMoveCount: Int { steps.count { $0.mine } }
    var ourMovesPlayed: Int { steps.prefix(cursor).count { $0.mine } }
    var missedCount: Int { missed.count }

    /// Solve: the last move of ours that was found, whose note says why it works.
    var solvedStep: LineStep? {
        guard flow == .solve, phase != .guided else { return nil }
        return steps.prefix(min(cursor, steps.count)).last { $0.mine }
    }

    /// 0…1 along the current pass.
    var progress: Double {
        steps.isEmpty ? 0 : Double(min(cursor, steps.count)) / Double(steps.count)
    }

    var canGoBack: Bool {
        phase == .guided && steps.prefix(min(cursor, steps.count)).contains { $0.mine }
    }

    /// The note the reading plate leads with. In the guided pass it is the
    /// note of the move about to be played; in the memory pass a note only
    /// shows after a miss or on demand.
    var leadStep: LineStep? {
        switch phase {
        case .guided: currentStep
        case .play: noteRevealed ? currentStep : nil
        case .finished: nil
        }
    }

    /// The opponent's last note stays under ours until our move is played.
    var trailingStep: LineStep? {
        guard phase == .guided, let current = currentStep, current.mine,
              let previous = previousStep, !previous.mine, !previous.comments.isEmpty
        else { return nil }
        return previous
    }

    var arrows: [BoardArrow] {
        guard !isBoardLocked else { return [] }
        var arrows: [BoardArrow] = []
        if phase == .guided, let previous = previousStep {
            arrows += previous.shapes.compactMap(Self.arrow(for:))
        }
        if let step = currentStep, let move = Move(uci: step.uci) {
            let shown = phase == .guided || (phase == .play && hintLevel >= 2 && step.mine)
            if shown {
                let move = position.normalized(move)
                arrows.append(BoardArrow(from: move.from, to: move.to, brush: step.mine ? .move : .reply))
            }
        }
        return arrows
    }

    var hintSquare: Square? {
        guard phase == .play, hintLevel == 1, let step = currentStep, step.mine else { return nil }
        return Move(uci: step.uci)?.from
    }

    private static func arrow(for shape: LineStep.Shape) -> BoardArrow? {
        guard let from = Square(shape.orig) else { return nil }
        return BoardArrow(
            from: from,
            to: shape.dest.flatMap { Square($0) },
            brush: BoardArrow.Brush(rawValue: shape.brush) ?? .idea
        )
    }

    // MARK: Lifecycle

    func start() {
        settle(first: true)
    }

    func stop() {
        pending?.cancel()
        pending = nil
    }

    /// Guided pass over: test it from memory.
    func startMemoryPass() {
        stop()
        phase = .play
        missed = []
        grades = []
        solvedAnotherWay = false
        isJudging = false
        rewind(to: 0)
        settle(first: true)
    }

    func learnAgain() {
        guard flow != .solve else { return startMemoryPass() }
        stop()
        phase = .guided
        rewind(to: 0)
        settle(first: true)
    }

    // MARK: Moves

    /// A move made on the board. Returns whether the board should keep
    /// showing it (see `BoardView.onMove`).
    func play(_ attempt: Move) -> Bool {
        guard isOurTurn, let step = currentStep, let expected = Move(uci: step.uci) else { return false }
        if position.normalized(attempt) == position.normalized(expected) {
            feedback = nil
            let square = position.normalized(expected).to
            advance()
            if phase == .play { verdict = BoardVerdict(square: square, kind: .right) }
            settle()
        } else if let judge, flow == .solve, let question = judgeQuestion(attempt, expected: step) {
            ask(judge, question, attempt: attempt)
        } else {
            holdWrong(attempt)
        }
        return true
    }

    /// When a different move may still be right while solving: a move that
    /// mates on the spot always is; otherwise the engine is asked, for an
    /// exercise that ends in mate (does this mate as fast?) and for the last
    /// move of any other exercise (is it as good?). Earlier moves must follow
    /// the course, whose replies are the only ones the trainer can play.
    private func judgeQuestion(_ attempt: Move, expected step: LineStep) -> JudgeQuestion? {
        guard let played = position.playing(attempt) else { return nil }
        let movesLeft = steps.dropFirst(cursor + 1).count { $0.mine }
        if steps.last?.san.hasSuffix("#") == true {
            if played.isCheckmate { return .accepted }
            return .mate(fenAfterPlayed: played.fen, within: movesLeft)
        }
        guard movesLeft == 0 else { return nil }
        return .equal(fenAfterPlayed: played.fen, fenAfterExpected: step.fenAfter)
    }

    private func ask(_ judge: any MoveJudging, _ question: JudgeQuestion, attempt: Move) {
        guard let shown = position.playing(attempt) else { return }
        stop()
        let home = position
        let homeLastMove = lastMove
        let tried = home.normalized(attempt)
        isBoardLocked = true
        isJudging = true
        feedback = nil
        position = shown
        lastMove = tried
        onMovePlayed(home.isCapture(tried))
        pending = Task { [weak self] in
            let accepted = await judge.accepts(question)
            guard !Task.isCancelled, let self else { return }
            self.isJudging = false
            if accepted {
                // As good as the course's move: the exercise is solved here.
                self.solvedAnotherWay = true
                self.verdict = BoardVerdict(square: tried.to, kind: .right)
                self.cursor = self.steps.count
                self.finishMemoryPass()
            } else {
                self.position = home
                self.lastMove = homeLastMove
                self.isBoardLocked = false
                self.holdWrong(attempt)
            }
        }
    }

    /// Guided pass shortcut: plays the next move for the learner, or brings
    /// the opponent's reply forward.
    func next() {
        guard phase == .guided, currentStep != nil, !isBoardLocked else { return }
        stop()
        feedback = nil
        advance()
        settle()
    }

    /// Guided pass: back to our previous move.
    func back() {
        guard canGoBack else { return }
        stop()
        let before = min(cursor, steps.count)
        guard let target = steps.prefix(before).lastIndex(where: { $0.mine }) else { return }
        rewind(to: target)
    }

    /// Memory pass hint ladder: the square to move from, then the arrow.
    func hint() {
        guard phase == .play, isOurTurn, hintLevel < 2 else { return }
        hintLevel += 1
        missed.insert(cursor)
    }

    func revealNote() {
        guard phase == .play, isOurTurn else { return }
        noteRevealed = true
    }

    // MARK: Engine

    private func rewind(to index: Int) {
        cursor = index
        position = Position(fen: index < steps.count ? steps[index].fenBefore : line.startFen) ?? .start
        lastMove = index > 0 ? Move(uci: steps[index - 1].uci).map { previousPosition(index).normalized($0) } : nil
        verdict = nil
        feedback = nil
        hintLevel = 0
        noteRevealed = false
        isBoardLocked = false
    }

    private func previousPosition(_ index: Int) -> Position {
        Position(fen: steps[index - 1].fenBefore) ?? .start
    }

    /// Shows the step at `cursor` as played and moves the cursor past it.
    private func advance() {
        guard let step = currentStep, let move = Move(uci: step.uci) else { return }
        let normalized = position.normalized(move)
        let capture = position.isCapture(normalized)
        // The server's position is the truth; ours is only checked in tests.
        position = Position(fen: step.fenAfter) ?? position.playing(normalized) ?? position
        lastMove = normalized
        verdict = nil
        hintLevel = 0
        noteRevealed = false
        cursor += 1
        onMovePlayed(capture)
    }

    /// After the cursor moved: let the opponent reply, or close the pass.
    private func settle(first: Bool = false) {
        stop()
        guard let step = currentStep else {
            // A lesson is done once it has been played through.
            if phase == .play || flow == .lesson { finishMemoryPass() }
            return
        }
        guard !step.mine else { return }
        let delay = first ? timing.firstMove : phase == .guided ? timing.opponentGuided : timing.opponentPlay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.advance()
            self.settle()
        }
    }

    private func holdWrong(_ attempt: Move) {
        guard let shown = position.playing(attempt) else { return }
        stop()
        let home = position
        let homeLastMove = lastMove
        if phase == .play {
            missed.insert(cursor)
            // While solving, the note explains the answer: it waits for the move.
            noteRevealed = flow != .solve
            feedback = .missed
        } else {
            feedback = .notThisOne
        }
        let tried = home.normalized(attempt)
        isBoardLocked = true
        position = shown
        lastMove = nil
        verdict = BoardVerdict(square: tried.to, kind: .wrong)
        onMovePlayed(home.isCapture(tried))
        pending = Task { [weak self] in
            try? await Task.sleep(for: self?.timing.wrongHold ?? .zero)
            guard !Task.isCancelled, let self else { return }
            self.position = home
            self.lastMove = homeLastMove
            self.verdict = nil
            self.isBoardLocked = false
        }
    }

    private func finishMemoryPass() {
        grades = steps.enumerated().compactMap { index, step in
            step.mine && gradedSteps?.contains(index) != false
                ? MoveGrade(fen: step.fenBefore, uci: step.uci, grade: missed.contains(index) ? .again : .good)
                : nil
        }
        isBoardLocked = true
        pending = Task { [weak self] in
            try? await Task.sleep(for: self?.timing.finish ?? .zero)
            guard !Task.isCancelled, let self else { return }
            self.phase = .finished
            self.verdict = nil
            self.onFinished(self.grades)
        }
    }
}

extension LineStep {
    /// "2… d5" / "3. exd5": the move with its number, as a chess book sets it.
    var numberLabel: String {
        let number = (ply + 1) / 2
        return ply.isMultiple(of: 2) ? "\(number)…" : "\(number)."
    }

    var note: String { comments.joined(separator: "\n\n") }
}
