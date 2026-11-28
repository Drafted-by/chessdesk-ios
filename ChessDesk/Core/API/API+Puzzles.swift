import Foundation

/// Rated puzzles, the free set and the Woodpecker Method. The server decides
/// what is served, the ratings, the cycles, the limits and the paywall; the
/// app plays the lines on the board (see `PuzzleSolver`). `ChessDeskAPI`
/// inherits it, which makes it `Sendable`.
nonisolated protocol PuzzlesAPI {
    /// The player's puzzle rating and recent results (nil for a visitor), and the themes.
    func puzzleOverview(token: String?) async throws -> PuzzleOverview
    /// The free set of the site's public trainer, easiest first. Nothing is recorded.
    func freePuzzles(theme: String?, band: String?, token: String?) async throws -> FreePuzzles
    /// Serves the next rated puzzle; it becomes the one an attempt is accepted for.
    func nextPuzzle(theme: String?, token: String) async throws -> Puzzle
    /// Records the outcome of the served puzzle, once. 409: the app's state is stale.
    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool, ms: Int?, token: String) async throws -> PuzzleAttempt

    func woodpecker(token: String) async throws -> WoodpeckerOverview
    /// Builds a set and opens cycle 1. 403 `premium_required` is the paywall.
    func createWoodpeckerSet(size: Int?, theme: String?, token: String) async throws -> WoodpeckerOverview
    /// Finishes (two completed cycles at least) or abandons the set being worked.
    func closeWoodpeckerSet(_ status: WoodpeckerSetStatus, token: String) async throws -> WoodpeckerOverview
    /// The answer to the expected puzzle of the open cycle; the last one closes the cycle.
    func recordWoodpeckerSolve(puzzleId: String, correct: Bool, ms: Int, token: String) async throws -> WoodpeckerStep
    func startWoodpeckerCycle(token: String) async throws -> WoodpeckerRun
    /// Retires a flawed puzzle for this cycle and every later one.
    func retireWoodpeckerPuzzle(_ puzzleId: String, token: String) async throws -> WoodpeckerStep
    func woodpeckerReport(token: String) async throws -> WoodpeckerReport
}

nonisolated extension LiveAPI: PuzzlesAPI {
    func puzzleOverview(token: String?) async throws -> PuzzleOverview {
        try await send("GET", "puzzles", token: token)
    }

    func freePuzzles(theme: String?, band: String?, token: String?) async throws -> FreePuzzles {
        var query: [URLQueryItem] = []
        if let theme { query.append(URLQueryItem(name: "theme", value: theme)) }
        if let band { query.append(URLQueryItem(name: "band", value: band)) }
        return try await send("GET", "puzzles/free", query: query, token: token)
    }

    func nextPuzzle(theme: String?, token: String) async throws -> Puzzle {
        try await send("POST", "puzzles/next", token: token, body: NextPuzzleRequest(theme: theme))
    }

    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool, ms: Int?, token: String) async throws -> PuzzleAttempt {
        try await send(
            "POST", "puzzles/\(puzzleId)/attempts", token: token,
            body: PuzzleAttemptRequest(solved: solved, ms: ms)
        )
    }

    func woodpecker(token: String) async throws -> WoodpeckerOverview {
        try await send("GET", "woodpecker", token: token)
    }

    func createWoodpeckerSet(size: Int?, theme: String?, token: String) async throws -> WoodpeckerOverview {
        // Building a set draws hundreds of puzzles: give it time.
        try await send("POST", "woodpecker/set", token: token, body: WoodpeckerSetRequest(size: size, theme: theme), timeout: 60)
    }

    func closeWoodpeckerSet(_ status: WoodpeckerSetStatus, token: String) async throws -> WoodpeckerOverview {
        try await send("PUT", "woodpecker/set", token: token, body: WoodpeckerSetStatusRequest(status: status))
    }

    func recordWoodpeckerSolve(puzzleId: String, correct: Bool, ms: Int, token: String) async throws -> WoodpeckerStep {
        try await send(
            "POST", "woodpecker/set/solves", token: token,
            body: WoodpeckerSolveRequest(puzzleId: puzzleId, correct: correct, ms: ms)
        )
    }

    func startWoodpeckerCycle(token: String) async throws -> WoodpeckerRun {
        try await send("POST", "woodpecker/set/cycles", token: token)
    }

    func retireWoodpeckerPuzzle(_ puzzleId: String, token: String) async throws -> WoodpeckerStep {
        try await send("DELETE", "woodpecker/set/puzzles/\(puzzleId)", token: token)
    }

    func woodpeckerReport(token: String) async throws -> WoodpeckerReport {
        try await send("GET", "woodpecker/report", token: token)
    }
}

/// The free set and the visitor's summary are captured in `Fixtures/api-v1`;
/// the rated side and Woodpecker need an account, as on the server.
nonisolated extension FixtureAPI: PuzzlesAPI {
    private var accountNeeded: APIError {
        .server(status: 401, code: "unauthorized", message: "Sign in to continue.")
    }

    func puzzleOverview(token: String?) async throws -> PuzzleOverview {
        try await Task.sleep(for: delay)
        return try LiveAPI.decode(status: 200, data: Self.data("puzzles"))
    }

    /// The captured answer is the whole free set; filtered here the way the
    /// server filters it (`selectPuzzles` in the site's `lib/puzzles/engine.ts`).
    func freePuzzles(theme: String?, band: String?, token: String?) async throws -> FreePuzzles {
        try await Task.sleep(for: delay)
        let all: FreePuzzles = try LiveAPI.decode(status: 200, data: Self.data("puzzles-free"))
        let range = band.flatMap { id in all.bands.first { $0.id == id } }
        let puzzles = all.puzzles.filter { puzzle in
            (theme == nil || puzzle.themes.contains { $0.id == theme })
                && (range == nil || (range!.min..<range!.max).contains(puzzle.rating))
        }
        return FreePuzzles(puzzles: puzzles, themes: all.themes, bands: all.bands)
    }

    func nextPuzzle(theme: String?, token: String) async throws -> Puzzle { throw accountNeeded }
    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool, ms: Int?, token: String) async throws -> PuzzleAttempt {
        throw accountNeeded
    }

    func woodpecker(token: String) async throws -> WoodpeckerOverview { throw accountNeeded }
    func createWoodpeckerSet(size: Int?, theme: String?, token: String) async throws -> WoodpeckerOverview { throw accountNeeded }
    func closeWoodpeckerSet(_ status: WoodpeckerSetStatus, token: String) async throws -> WoodpeckerOverview { throw accountNeeded }
    func recordWoodpeckerSolve(puzzleId: String, correct: Bool, ms: Int, token: String) async throws -> WoodpeckerStep {
        throw accountNeeded
    }
    func startWoodpeckerCycle(token: String) async throws -> WoodpeckerRun { throw accountNeeded }
    func retireWoodpeckerPuzzle(_ puzzleId: String, token: String) async throws -> WoodpeckerStep { throw accountNeeded }
    func woodpeckerReport(token: String) async throws -> WoodpeckerReport { throw accountNeeded }
}
