import ChessCore
import Foundation
import Observation

/// What the board shows: usually the solver's position, for a beat the
/// player's move before the reply, or a wrong try before it goes back.
struct PuzzleBoard: Equatable {
    var position: Position
    var lastMove: Move?
    var verdict: BoardVerdict?
}

/// The puzzle trainer, free or rated. A port of the state of the site's
/// `apps/web/components/puzzle-trainer.tsx`:
///
/// - a wrong move is refused, shown for a beat, and the player tries again;
/// - the Hint shows the square the expected move starts from, and reveals the themes;
/// - a puzzle is *solved* only when the whole line is played with no wrong
///   move and no hint. Anything else (wrong try, hint, skip, and in the app
///   the solution shown) is a miss;
/// - rated: the outcome is sent once, when the player moves on, before the
///   next puzzle is served (serving again replaces the served puzzle);
/// - free: nothing is sent; the streak and the solved puzzles stay on the device.
@Observable
final class PuzzleTrainerModel {
    enum Source: Equatable { case free, rated }
    enum Feedback: Equatable { case idle, correct, wrong, solved, completed, revealed }
    enum Phase: Equatable { case loading, ready, empty, failed(String) }

    let source: Source
    private let api: any PuzzlesAPI & Sendable
    private let token: () -> String?
    private let store: FreePuzzleProgressStore
    private let now: () -> Date

    /// How long a wrong try stays on the board.
    var wrongBeat: Duration = .milliseconds(900)
    /// The pause before the opponent's move, so the player sees it played.
    var replyDelay: Duration = .milliseconds(420)

    private(set) var phase: Phase = .loading
    private(set) var puzzle: Puzzle?
    private(set) var solver: PuzzleSolver?
    private(set) var board: PuzzleBoard?
    private(set) var feedback: Feedback = .idle
    private(set) var showsHint = false
    /// A hint was taken on this puzzle: its themes may be shown.
    private(set) var hintUsed = false
    /// No wrong move, no hint, no solution shown so far.
    private(set) var isClean = true
    private var animations = 0
    /// A move is being shown (setup, reply, wrong try): the board waits.
    var isAnimating: Bool { animations > 0 || isRevealing }
    private var isRevealing = false
    private(set) var isBusy = false

    // Free set
    private(set) var freeThemes: [PuzzleTheme] = []
    private(set) var bands: [PuzzleBand] = []
    private(set) var theme: String?
    private(set) var band: String?
    private(set) var puzzles: [Puzzle] = []
    private(set) var index = 0
    private(set) var solvedIDs: Set<String>

    // Rated
    private(set) var themeGroups: [PuzzleThemeGroup] = []
    private(set) var rating: Int?
    private(set) var lastDelta: Int?
    /// A result that could not be saved; Retry sends it again.
    private(set) var submitError: String?
    /// Something the player should know that is not an error.
    private(set) var notice: String?
    private var pendingSubmit: (id: String, solved: Bool, ms: Int)?
    private var resolved = true
    private var startedAt = Date.distantPast

    private(set) var streak: Int
    private(set) var bestStreak: Int

    init(
        source: Source,
        api: any PuzzlesAPI & Sendable,
        token: @escaping () -> String?,
        store: FreePuzzleProgressStore = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.api = api
        self.token = token
        self.store = store
        self.now = now
        if source == .free {
            streak = store.streak
            bestStreak = store.bestStreak
            solvedIDs = store.solved
        } else {
            streak = 0
            bestStreak = 0
            solvedIDs = []
        }
    }

    // MARK: Derived

    var isLineOver: Bool { solver?.isSolved ?? false }

    /// The side that may move, nil while the board is locked.
    var movableSide: Side? {
        guard phase == .ready, let solver, !solver.isSolved, !isAnimating, !isBusy else { return nil }
        return solver.solverSide
    }

    var hintSquare: Square? { showsHint ? solver?.hintSquare : nil }

    var solvedInSet: Int { puzzles.filter { solvedIDs.contains($0.id) }.count }

    // MARK: Loading

    func start() async {
        switch source {
        case .free: await loadFree()
        case .rated:
            phase = .loading
            await readOverview()
            await serve()
        }
    }

    private func loadFree() async {
        phase = .loading
        do {
            let set = try await api.freePuzzles(theme: theme, band: band, token: token())
            freeThemes = set.themes
            bands = set.bands
            puzzles = set.puzzles
            index = 0
            if let first = puzzles.first {
                present(first)
                phase = .ready
            } else {
                puzzle = nil
                solver = nil
                board = nil
                phase = .empty
            }
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    /// The free set again, with other filters.
    func setFilters(theme: String?, band: String?) async {
        guard source == .free, theme != self.theme || band != self.band else { return }
        self.theme = theme
        self.band = band
        await loadFree()
    }

    /// Rated: the theme of the puzzles to serve. The current puzzle's outcome is sent first.
    func setRatedTheme(_ theme: String?) async {
        guard source == .rated, theme != self.theme else { return }
        self.theme = theme
        if await finish() { await serve() }
    }

    private func readOverview() async {
        guard let overview = try? await api.puzzleOverview(token: token()) else { return }
        themeGroups = overview.themeGroups
        if let player = overview.player { rating = player.rating }
    }

    private func serve() async {
        guard let token = token() else {
            phase = .failed("Sign in to solve rated puzzles.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let served = try await api.nextPuzzle(theme: theme, token: token)
            present(served)
            resolved = false
            startedAt = now()
            phase = .ready
        } catch {
            puzzle = nil
            solver = nil
            board = nil
            resolved = true
            phase = .failed(Self.message(error))
        }
    }

    private func present(_ next: Puzzle) {
        puzzle = next
        solver = PuzzleSolver(next)
        feedback = .idle
        showsHint = false
        hintUsed = false
        isClean = true
        guard let solver else {
            board = nil
            return
        }
        // The opponent's setup move is played on the board, not skipped.
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

    /// A move made on the board. True when the board shows the result.
    func play(_ move: Move) -> Bool {
        guard movableSide != nil, var next = solver, let before = board?.position else { return false }
        let graded = next.gradedMove(move)
        switch next.submit(move) {
        case .illegal:
            return false
        case .wrong:
            // A wrong move never ends the puzzle: shown for a beat, then taken back.
            isClean = false
            showsHint = false
            feedback = .wrong
            guard let tried = next.trying(move) else { return false }
            board = PuzzleBoard(position: tried, lastMove: graded, verdict: BoardVerdict(square: graded.to, kind: .wrong))
            let id = puzzle?.id
            animate(after: wrongBeat) { [weak self] in
                guard let self, self.puzzle?.id == id, let current = self.solver else { return }
                self.board = PuzzleBoard(position: current.position, lastMove: current.lastMove)
            }
            return true
        case let .correct(reply):
            solver = next
            showsHint = false
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
            showsHint = false
            lineCompleted()
            return true
        }
    }

    private func lineCompleted() {
        guard let solver else { return }
        let move = solver.lastMove
        board = PuzzleBoard(
            position: solver.position,
            lastMove: move,
            verdict: move.map { BoardVerdict(square: $0.to, kind: .right) }
        )
        if feedback != .revealed { feedback = isClean ? .solved : .completed }
        guard source == .free, isClean, let id = puzzle?.id else { return }
        // The free streak counts first-time clean solves, as on the site.
        if !solvedIDs.contains(id) { streak += 1 }
        solvedIDs.insert(id)
        bestStreak = max(bestStreak, streak)
        store.save(streak: streak, best: bestStreak, solved: solvedIDs)
    }

    /// Shows where the expected move starts. The puzzle is no longer clean.
    func hint() {
        guard movableSide != nil else { return }
        isClean = false
        showsHint = true
        hintUsed = true
    }

    /// Plays the rest of the line on the board. The puzzle counts as missed.
    func showSolution() async {
        guard movableSide != nil, let id = puzzle?.id else { return }
        isClean = false
        showsHint = false
        hintUsed = true
        feedback = .revealed
        isRevealing = true
        defer { isRevealing = false }
        while var next = solver, let expected = next.expectedMove, puzzle?.id == id {
            let before = next.position
            let result = next.submit(expected)
            solver = next
            if case .correct(reply: .some) = result, let afterMove = before.playing(expected) {
                board = PuzzleBoard(position: afterMove, lastMove: expected)
                try? await Task.sleep(for: replyDelay)
                guard puzzle?.id == id else { return }
                board = PuzzleBoard(position: next.position, lastMove: next.lastMove)
                try? await Task.sleep(for: replyDelay)
            } else if result == .solved {
                lineCompleted()
                return
            } else {
                return
            }
        }
    }

    // MARK: Moving on

    /// The next puzzle. Rated: the outcome is sent first; a result that could
    /// not be saved keeps this puzzle up, with Retry.
    func next() async {
        switch source {
        case .free:
            guard !puzzles.isEmpty else { return }
            index = (index + 1) % puzzles.count
            present(puzzles[index])
        case .rated:
            guard !isBusy else { return }
            isBusy = true
            let submitted = await finish()
            isBusy = false
            if submitted { await serve() }
        }
    }

    /// Sends the outcome of the served puzzle, once. False when it could not be saved.
    private func finish() async -> Bool {
        guard source == .rated, !resolved, let id = puzzle?.id else { return true }
        resolved = true
        let solved = isLineOver && isClean
        let ms = max(0, Int(now().timeIntervalSince(startedAt) * 1000))
        streak = solved ? streak + 1 : 0
        bestStreak = max(bestStreak, streak)
        return await submit(id: id, solved: solved, ms: ms)
    }

    private func submit(id: String, solved: Bool, ms: Int) async -> Bool {
        guard let token = token() else { return true }
        notice = nil
        do {
            let attempt = try await api.recordPuzzleAttempt(id, solved: solved, ms: ms, token: token)
            rating = attempt.rating
            lastDelta = attempt.delta
            pendingSubmit = nil
            submitError = nil
            return true
        } catch let error as APIError where error.code == "request_failed" && Self.status(error) == 409 {
            // The server moved on (another device served a puzzle): read it again.
            pendingSubmit = nil
            submitError = nil
            notice = "That result was not saved: the puzzle had changed. Here is a fresh one."
            lastDelta = nil
            await readOverview()
            return true
        } catch {
            pendingSubmit = (id, solved, ms)
            submitError = "Result not saved: \(Self.message(error))"
            return false
        }
    }

    func retrySubmit() async {
        guard let pending = pendingSubmit, !isBusy else { return }
        isBusy = true
        _ = await submit(id: pending.id, solved: pending.solved, ms: pending.ms)
        isBusy = false
    }

    // MARK: Helpers

    /// Waits until the moves being shown are on the board.
    func settle() async {
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

    static func message(_ error: any Error) -> String {
        (error as? APIError ?? .unreadable).message
    }

    static func status(_ error: APIError) -> Int? {
        if case let .server(status, _, _) = error { return status }
        return nil
    }
}

/// The free set's progress on this device: what the site keeps in localStorage.
struct FreePuzzleProgressStore {
    let defaults: UserDefaults

    static let standard = FreePuzzleProgressStore(defaults: .standard)

    private static let streakKey = "cd.puzzles.streak"
    private static let bestKey = "cd.puzzles.beststreak"
    private static let solvedKey = "cd.puzzles.solved"

    var streak: Int { max(0, defaults.integer(forKey: Self.streakKey)) }
    var bestStreak: Int { max(0, defaults.integer(forKey: Self.bestKey)) }
    var solved: Set<String> { Set(defaults.stringArray(forKey: Self.solvedKey) ?? []) }

    func save(streak: Int, best: Int, solved: Set<String>) {
        defaults.set(streak, forKey: Self.streakKey)
        defaults.set(max(best, bestStreak), forKey: Self.bestKey)
        defaults.set(solved.sorted(), forKey: Self.solvedKey)
    }
}
