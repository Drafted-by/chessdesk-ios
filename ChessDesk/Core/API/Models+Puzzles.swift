import Foundation

// Models of `/api/v1/puzzles*` and `/api/v1/woodpecker*`, as the contract
// (`contracts/openapi-v1.json`) describes them. The API is additive: unknown
// fields are ignored, and enums the app may not know yet decode to `unknown`.

// MARK: Puzzles

nonisolated struct PuzzleTheme: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
}

nonisolated struct PuzzleThemeGroup: Codable, Sendable, Hashable {
    let group: String
    let themes: [PuzzleTheme]
}

/// A tactics puzzle in the Lichess shape: `fen` is the position before the
/// opponent's setup move `moves[0]`; the solver then finds `moves[1]`,
/// `moves[3]`… while `moves[2]`, `moves[4]`… are the forced replies.
nonisolated struct Puzzle: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int
    let themes: [PuzzleTheme]
}

/// A difficulty band of the free set: `min` inclusive, `max` exclusive.
nonisolated struct PuzzleBand: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let min: Int
    let max: Int
}

/// The free set of the site's public trainer, easiest first. Nothing is recorded.
nonisolated struct FreePuzzles: Codable, Sendable, Hashable {
    let puzzles: [Puzzle]
    let themes: [PuzzleTheme]
    let bands: [PuzzleBand]
}

nonisolated struct PuzzlePlayer: Codable, Sendable, Hashable {
    nonisolated struct Recent: Codable, Sendable, Hashable {
        let attempts: Int
        let solved: Int
    }

    nonisolated struct Point: Codable, Sendable, Hashable {
        let at: Date
        let rating: Int
        let solved: Bool
    }

    let rating: Int
    let deviation: Int
    let solved: Int
    let attempts: Int
    let last30Days: Recent
    /// The last rating points, oldest first.
    let history: [Point]
}

/// The puzzle summary: the player's rating (nil for a visitor) and the themes.
nonisolated struct PuzzleOverview: Codable, Sendable, Hashable {
    nonisolated struct Free: Codable, Sendable, Hashable {
        let puzzles: Int
    }

    let player: PuzzlePlayer?
    let themeGroups: [PuzzleThemeGroup]
    let free: Free
}

nonisolated struct NextPuzzleRequest: Codable, Sendable {
    let theme: String?
}

nonisolated struct PuzzleAttemptRequest: Codable, Sendable {
    let solved: Bool
    let ms: Int?
}

/// The rating after an attempt, and its change as the site shows it.
nonisolated struct PuzzleAttempt: Codable, Sendable, Hashable {
    let rating: Int
    let delta: Int
    let deviation: Int
    let solved: Int
}

// MARK: Woodpecker

nonisolated struct WoodpeckerPuzzle: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int
}

/// A completed cycle against its halving target (none for cycle 1).
nonisolated struct WoodpeckerCycle: Codable, Sendable, Hashable, Identifiable {
    let cycleNumber: Int
    let durationMs: Int
    let correct: Int
    let total: Int
    let accuracy: Double
    let targetMs: Int?
    let targetBeaten: Bool?

    var id: Int { cycleNumber }
}

nonisolated struct WoodpeckerRun: Codable, Sendable, Hashable {
    nonisolated struct PuzzleSet: Codable, Sendable, Hashable {
        let id: String
        let size: Int
        let theme: PuzzleTheme?
        let baseRating: Int
        let spread: Int
        let createdAt: Date
        let retired: Int
        let remaining: Int
        let discovery: Bool
    }

    nonisolated struct OpenCycle: Codable, Sendable, Hashable {
        let cycleNumber: Int
        let startedAt: Date
        let solved: Int
        let total: Int
        let targetMs: Int?
    }

    nonisolated struct NextCycle: Codable, Sendable, Hashable {
        nonisolated enum State: String, Codable, Sendable, Hashable {
            case allowed
            case afterCycle = "after_cycle"
            case premiumRequired = "premium_required"
            case unavailable
            case unknown

            init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = State(rawValue: raw) ?? .unknown
            }
        }

        let state: State
        let cycleNumber: Int
        let targetMs: Int?
        let message: String?
    }

    /// What may happen between two cycles.
    nonisolated struct Between: Codable, Sendable, Hashable {
        let nextCycle: NextCycle
        let canComplete: Bool
        let cyclesToComplete: Int
        let cycleLimit: Int
    }

    let set: PuzzleSet
    let cycles: [WoodpeckerCycle]
    /// Nil between two cycles.
    let openCycle: OpenCycle?
    let expectedPuzzleId: String?
    /// The next puzzles of the open cycle, in order, the expected one first.
    let puzzles: [WoodpeckerPuzzle]
    let between: Between
}

nonisolated struct WoodpeckerSavedSet: Codable, Sendable, Hashable, Identifiable {
    nonisolated struct Unfinished: Codable, Sendable, Hashable {
        let cycleNumber: Int
        let correct: Int
        let total: Int
    }

    let id: String
    let size: Int
    let status: String
    let cycles: [WoodpeckerCycle]
    let unfinished: [Unfinished]
}

/// Everything the Woodpecker screen needs; `state` is the screen to show.
nonisolated struct WoodpeckerOverview: Codable, Sendable, Hashable {
    nonisolated enum State: String, Codable, Sendable, Hashable {
        case run, discovery
        case premiumRequired = "premium_required"
        case calibrate, create
        case unknown

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    nonisolated struct Calibration: Codable, Sendable, Hashable {
        let attempts: Int
        let required: Int
        let calibrated: Bool
    }

    nonisolated struct Discovery: Codable, Sendable, Hashable {
        let used: Bool
        let size: Int
        let cycles: Int
    }

    nonisolated struct Creation: Codable, Sendable, Hashable {
        nonisolated struct Sizes: Codable, Sendable, Hashable {
            let min: Int
            let max: Int
            let `default`: Int
            let presets: [Int]
        }

        let sizes: Sizes
        let themeGroups: [PuzzleThemeGroup]
    }

    let state: State
    let premium: Bool
    let calibration: Calibration
    let discovery: Discovery
    let completedSets: Int
    let creation: Creation
    let run: WoodpeckerRun?
    let history: [WoodpeckerSavedSet]
}

nonisolated struct WoodpeckerStep: Codable, Sendable, Hashable {
    let cycleDone: Bool
    let run: WoodpeckerRun
}

nonisolated struct WoodpeckerReport: Codable, Sendable, Hashable {
    nonisolated struct TroubleSpot: Codable, Sendable, Hashable, Identifiable {
        let puzzleId: String
        let wrong: Int
        let avgMs: Int
        let rating: Int
        let fen: String
        let orientation: String

        var id: String { puzzleId }
    }

    let setId: String
    let status: String
    let size: Int
    let theme: PuzzleTheme?
    let retired: Int
    let cycles: [WoodpeckerCycle]
    let timeSavedPercent: Int?
    let troubleSpots: [TroubleSpot]
}

nonisolated struct WoodpeckerSetRequest: Codable, Sendable {
    let size: Int?
    let theme: String?
}

nonisolated enum WoodpeckerSetStatus: String, Codable, Sendable {
    case completed, abandoned
}

nonisolated struct WoodpeckerSetStatusRequest: Codable, Sendable {
    let status: WoodpeckerSetStatus
}

nonisolated struct WoodpeckerSolveRequest: Codable, Sendable {
    let puzzleId: String
    let correct: Bool
    let ms: Int
}

nonisolated enum WoodpeckerFormat {
    /// m:ss, or h:mm:ss past an hour. Port of the site's `lib/woodpecker/format.ts`.
    static func time(_ ms: Int) -> String {
        let totalSeconds = max(0, Int((Double(ms) / 1000).rounded()))
        let s = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let m = totalMinutes % 60
        let h = totalMinutes / 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
        return "\(m):\(ss)"
    }
}
