import ChessCore
import Foundation
import Observation

/// The Woodpecker Method: one fixed set, solved again and again in timed
/// cycles. The server decides which screen to show, the order of the
/// puzzles, the cycles, the targets, the limits and the paywall; this model
/// plays the board and the clock. A port of the site's
/// `apps/web/components/woodpecker/run.tsx`:
///
/// - no hint, no skip, no second try: the first wrong move ends the puzzle;
/// - each answer is sent with the time spent on that puzzle, and the cycle's
///   clock is the sum of the times sent plus the current puzzle;
/// - puzzles come in the server's order (`expectedPuzzleId`), never the app's.
@Observable
final class WoodpeckerModel {
    enum Screen: Equatable {
        case loading
        case failed(String)
        /// No set being worked: discovery, paywall, calibration or creation (`overview.state`).
        case entry
        case solving
        /// Between two cycles (`run.openCycle` is nil).
        case between
        case report
    }

    enum Feedback: Equatable { case idle, correct, wrong, solved }

    private let api: any PuzzlesAPI & Sendable
    private let token: () -> String?
    private let now: () -> Date

    /// How long a miss and a solve stay on screen before the next puzzle (the site's beats).
    var wrongBeat: Duration = .milliseconds(1100)
    var solvedBeat: Duration = .milliseconds(600)
    var replyDelay: Duration = .milliseconds(380)

    private(set) var screen: Screen = .loading
    private(set) var overview: WoodpeckerOverview?
    private(set) var run: WoodpeckerRun?
    private(set) var report: WoodpeckerReport?
    private(set) var puzzle: WoodpeckerPuzzle?
    private(set) var solver: PuzzleSolver?
    private(set) var board: PuzzleBoard?
    private(set) var feedback: Feedback = .idle
    /// The current puzzle is over, right or wrong, and the run is moving on.
    private(set) var ended = false
    private(set) var isBusy = false
    /// A refusal or a failure to show where it happened.
    private(set) var error: String?
    /// The server answered `premium_required`: the view shows the Premium sheet.
    var showsPremium = false

    /// Solve times sent during this cycle, in this session.
    private(set) var sessionMs = 0
    private var puzzleStartedAt: Date?
    private var resolved = false
    private var animations = 0
    private var pending: Task<Void, Never>?

    init(api: any PuzzlesAPI & Sendable, token: @escaping () -> String?, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.token = token
        self.now = now
    }

    // MARK: Derived

    var movableSide: Side? {
        guard screen == .solving, let solver, !solver.isSolved, !ended, !isBusy, animations == 0 else { return nil }
        return solver.solverSide
    }

    /// The expected puzzle's data is gone: the run can only go on by retiring it.
    var isMissingPuzzle: Bool {
        guard let run, run.openCycle != nil, run.expectedPuzzleId != nil else { return false }
        return puzzle == nil
    }

    /// The cycle's clock: the times sent plus the puzzle on the board.
    func elapsedMs(at date: Date) -> Int {
        guard screen == .solving, !ended, let start = puzzleStartedAt else { return sessionMs }
        return sessionMs + max(0, Int(date.timeIntervalSince(start) * 1000))
    }

    var targetMs: Int? { run?.openCycle?.targetMs }

    // MARK: Loading

    func load() async {
        if overview == nil { screen = .loading }
        do {
            apply(try await api.woodpecker(token: requireToken()))
        } catch {
            screen = .failed(Self.message(error))
        }
    }

    private func apply(_ overview: WoodpeckerOverview) {
        self.overview = overview
        report = nil
        if overview.state == .run, let run = overview.run {
            apply(run)
        } else {
            run = nil
            clearPuzzle()
            screen = .entry
        }
    }

    private func apply(_ run: WoodpeckerRun) {
        self.run = run
        guard run.openCycle != nil else {
            clearPuzzle()
            screen = .between
            return
        }
        screen = .solving
        // The server's order: only the expected puzzle may be played.
        if let expected = run.expectedPuzzleId, let next = run.puzzles.first(where: { $0.id == expected }) {
            present(next)
        } else {
            clearPuzzle()
        }
    }

    private func clearPuzzle() {
        puzzle = nil
        solver = nil
        board = nil
        ended = false
        puzzleStartedAt = nil
    }

    private func present(_ next: WoodpeckerPuzzle) {
        if puzzle?.id == next.id, !ended { return }
        puzzle = next
        solver = PuzzleSolver(next)
        feedback = .idle
        ended = false
        resolved = false
        puzzleStartedAt = now()
        guard let solver else {
            board = nil
            return
        }
        if solver.solutionIndex == 1, let start = Position(fen: next.fen) {
            board = PuzzleBoard(position: start)
            animate(after: replyDelay) { [weak self] in
                guard let self, self.puzzle?.id == next.id, let current = self.solver else { return }
                self.board = PuzzleBoard(position: current.position, lastMove: current.lastMove)
            }
        } else {
            board = PuzzleBoard(position: solver.position, lastMove: solver.lastMove)
        }
    }

    // MARK: Solving

    func play(_ move: Move) -> Bool {
        guard movableSide != nil, var next = solver, let before = board?.position else { return false }
        let graded = next.gradedMove(move)
        switch next.submit(move) {
        case .illegal:
            return false
        case .wrong:
            // The first wrong move ends the puzzle; the refused move stays marked.
            feedback = .wrong
            ended = true
            if let tried = next.trying(move) {
                board = PuzzleBoard(position: tried, lastMove: graded, verdict: BoardVerdict(square: graded.to, kind: .wrong))
            }
            pending = Task { await finishPuzzle(correct: false) }
            return true
        case let .correct(reply):
            solver = next
            feedback = .correct
            if reply != nil, let afterMove = before.playing(graded) {
                board = PuzzleBoard(position: afterMove, lastMove: graded)
                let id = puzzle?.id
                animate(after: replyDelay) { [weak self] in
                    guard let self, self.puzzle?.id == id, let current = self.solver else { return }
                    self.board = PuzzleBoard(position: current.position, lastMove: current.lastMove)
                }
            } else {
                board = PuzzleBoard(position: next.position, lastMove: next.lastMove)
            }
            return true
        case .solved:
            solver = next
            feedback = .solved
            ended = true
            board = PuzzleBoard(
                position: next.position,
                lastMove: next.lastMove,
                verdict: next.lastMove.map { BoardVerdict(square: $0.to, kind: .right) }
            )
            pending = Task { await finishPuzzle(correct: true) }
            return true
        }
    }

    /// Sends the answer with its time, then shows the next puzzle or the end of the cycle.
    private func finishPuzzle(correct: Bool) async {
        guard let id = puzzle?.id, !resolved else { return }
        resolved = true
        let finishedAt = now()
        let ms = max(0, Int(finishedAt.timeIntervalSince(puzzleStartedAt ?? finishedAt) * 1000))
        sessionMs += ms
        let beat = correct ? solvedBeat : wrongBeat
        let started = ContinuousClock.now
        do {
            let step = try await api.recordWoodpeckerSolve(puzzleId: id, correct: correct, ms: ms, token: requireToken())
            try? await Task.sleep(until: started + beat)
            apply(step.run)
        } catch let failure as APIError where Self.status(failure) == 409 {
            // The run moved on elsewhere: read it again and carry on from there.
            try? await Task.sleep(until: started + beat)
            await load()
        } catch {
            self.error = "\(Self.message(error)) Reload to carry on."
        }
    }

    /// Retires a flawed puzzle from this cycle and every later one.
    func retire() async {
        guard let id = puzzle?.id ?? run?.expectedPuzzleId, !isBusy else { return }
        resolved = true
        await perform {
            let step = try await self.api.retireWoodpeckerPuzzle(id, token: self.requireToken())
            self.apply(step.run)
        }
    }

    // MARK: Between cycles and sets

    func create(size: Int?, theme: String?) async {
        await perform {
            let overview = try await self.api.createWoodpeckerSet(size: size, theme: theme, token: self.requireToken())
            self.sessionMs = 0
            self.apply(overview)
        }
    }

    func startNextCycle() async {
        await perform {
            let run = try await self.api.startWoodpeckerCycle(token: self.requireToken())
            self.sessionMs = 0
            self.apply(run)
        }
    }

    /// Finishes the set (two completed cycles at least), then shows its report.
    func finishSet() async {
        await perform {
            let overview = try await self.api.closeWoodpeckerSet(.completed, token: self.requireToken())
            self.overview = overview
            self.run = nil
            self.clearPuzzle()
            self.report = try await self.api.woodpeckerReport(token: self.requireToken())
            self.screen = .report
        }
    }

    /// Abandons the set; its results stay saved.
    func abandon() async {
        await perform {
            let overview = try await self.api.closeWoodpeckerSet(.abandoned, token: self.requireToken())
            self.sessionMs = 0
            self.apply(overview)
        }
    }

    /// The report of the latest set, whatever its status.
    func openReport() async {
        await perform {
            self.report = try await self.api.woodpeckerReport(token: self.requireToken())
            self.screen = .report
        }
    }

    /// From the report back to the entry screen.
    func closeReport() async {
        report = nil
        await load()
    }

    /// Runs one action: a paywall opens the Premium sheet, a 409 reads the
    /// state again, a 422 (a rule saying no) shows its message.
    private func perform(_ action: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await action()
        } catch let failure as APIError where failure.isPremiumRequired {
            showsPremium = true
        } catch let failure as APIError where Self.status(failure) == 409 {
            isBusy = false
            await load()
        } catch {
            self.error = Self.message(error)
        }
    }

    // MARK: Helpers

    /// Waits for the answer being sent and the moves being shown.
    func settle() async {
        await pending?.value
        while animations > 0 { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func animate(after delay: Duration, _ step: @escaping @MainActor () -> Void) {
        animations += 1
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            step()
            self?.animations -= 1
        }
    }

    private func requireToken() throws -> String {
        guard let token = token() else {
            throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to use the Woodpecker Method.")
        }
        return token
    }

    static func message(_ error: any Error) -> String {
        (error as? APIError ?? .unreadable).message
    }

    static func status(_ error: APIError) -> Int? {
        if case let .server(status, _, _) = error { return status }
        return nil
    }
}
