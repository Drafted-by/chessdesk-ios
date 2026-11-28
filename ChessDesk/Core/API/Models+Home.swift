import Foundation

// The signed-in player's home, progress and Daily 5 habit: `GET /api/v1/home`,
// `/progress`, `/progress/patterns/{key}`, `/daily` and the habit operations.
// The site computes all of it (`lib/player/today.ts`, `lib/habit/*`); the app
// shows it. Every enumerated value the server sends is read as a string
// (`Lenient`): a value added on the site after this app was built must never
// stop a screen from loading.

/// A string the server sends from a closed list. `value` is nil for a value
/// this version of the app does not know; the screen then leaves it out.
nonisolated struct Lenient<Value: RawRepresentable & Hashable & Sendable>: Codable, Hashable, Sendable
    where Value.RawValue == String
{
    let raw: String

    init(_ value: Value) { raw = value.rawValue }
    init(raw: String) { self.raw = raw }

    var value: Value? { Value(rawValue: raw) }

    init(from decoder: Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// W, L or D, from the player's side.
nonisolated enum GameResultLetter: String, Hashable, Sendable {
    case win = "W", loss = "L", draw = "D"
}

/// Where today's Daily 5 positions come from.
nonisolated enum DailySource: String, Codable, Hashable, Sendable {
    case mistakes, puzzles
}

/// How the Daily 5 reminder reaches the player. `push` is a browser
/// notification set up on the site; the app has no way to register for it.
nonisolated enum ReminderChannel: String, Codable, Hashable, Sendable {
    case off, email, push
}

/// The Daily 5 streak (`lib/habit/streak.ts`, `StreakStatus`).
nonisolated struct DailyStreak: Codable, Hashable, Sendable {
    let current: Int
    let longest: Int
    let freezes: Int
    let doneToday: Bool
    let coveredByFreeze: Int
    let nextFreezeIn: Int?
}

/// One step of Today's plan, in the server's order (`lib/player/today.ts`).
nonisolated struct TodayStep: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Hashable, Sendable {
        case daily, coach, review, path, course, courses, mistakes, deck, puzzles, play
    }

    nonisolated struct Target: Codable, Hashable, Sendable {
        let kind: Lenient<Kind>
        /// review: the game.
        let gameId: String?
        /// path, course: the slug.
        let slug: String?
        /// deck: "course:<slug>" or "repertoire:<id>", when known.
        let deck: String?
        /// coach: the assignment.
        let assignmentId: String?
    }

    let key: String
    let title: String
    let detail: String
    let minutes: Int
    let cta: String
    var primary: Bool
    let target: Target

    var id: String { key }
}

nonisolated struct PlayerHome: Codable, Hashable, Sendable {
    nonisolated struct Stats: Codable, Hashable, Sendable {
        let gamesThisWeek: Int
        let accuracy: Double?
        let errorsPerGame: Double?
        let reviewedGames: Int
    }

    nonisolated struct ToReview: Codable, Hashable, Sendable {
        let gameId: String
        let opponent: String
        let result: Lenient<GameResultLetter>
        let playedAt: Date
    }

    nonisolated struct Mistakes: Codable, Hashable, Sendable {
        let due: Int
        let total: Int
        let mastered: Int
    }

    nonisolated struct Daily: Codable, Hashable, Sendable {
        /// The player's local day, YYYY-MM-DD.
        var day: String
        var doneToday: Bool
        let source: Lenient<DailySource>
        let count: Int
        /// "Day 4 · next freeze day in 3 days", written by the server.
        var line: String
        var streak: DailyStreak
        /// The days of the last weeks with a finished Daily 5, YYYY-MM-DD.
        var recentDays: [String]
    }

    nonisolated struct Pulse: Codable, Hashable, Sendable {
        nonisolated struct Week: Codable, Hashable, Sendable {
            let wins: Int
            let draws: Int
            let losses: Int
        }

        nonisolated struct Rating: Codable, Hashable, Sendable {
            nonisolated struct Point: Codable, Hashable, Sendable {
                let at: Date
                let rating: Int
                let opponent: String
                let opponentElo: Int?
                let result: Lenient<GameResultLetter>
            }

            let timeClass: String
            let current: Int
            let delta: Int?
            let series: [Int]
            let points: [Point]
        }

        nonisolated struct BestWin: Codable, Hashable, Sendable {
            let opponent: String
            let elo: Int
            let gameId: String
            let playedAt: Date
        }

        /// Games per day, oldest first, the last day being today.
        let activity: [Int]
        let activityTotal: Int
        let streak: Int
        let week: Week
        let rating: Rating?
        let bestWin: BestWin?
    }

    nonisolated struct Onboarding: Codable, Hashable, Sendable {
        nonisolated struct FirstReport: Codable, Hashable, Sendable {
            nonisolated struct Blunder: Codable, Hashable, Sendable {
                let gameId: String
                let ply: Int
                let san: String
                let moveLabel: String
                let bestSan: String
                let classification: Lenient<MoveClass>
                let winLoss: Double
                let opponent: String
            }

            nonisolated struct Opening: Codable, Hashable, Sendable {
                let name: String
                let games: Int
                let wins: Int
                let draws: Int
                let losses: Int
                let pct: Double?
            }

            let batchGames: Int
            let reviewedGames: Int
            let accuracy: Double?
            let blunder: Blunder?
            let opening: Opening?
            let drillPositions: Int
            let provider: Lenient<GameProvider>?
            let pendingGameIds: [String]
        }

        /// "Where do you play?" has not been answered or skipped yet.
        var needsWelcome: Bool
        let autoReview: Bool
        let reviewQueue: [String]
        var firstReport: FirstReport?
    }

    var totalGames: Int
    let stats: Stats
    let toReview: ToReview?
    let mistakes: Mistakes
    var today: [TodayStep]
    var daily: Daily
    let puzzleRating: Double?
    let pulse: Pulse
    var progress: HomeProgress?
    var onboarding: Onboarding
}

/// Mistakes mastered, patterns, the rating goal (`lib/habit/progress-server.ts`).
nonisolated struct HomeProgress: Codable, Hashable, Sendable {
    nonisolated struct Mastered: Codable, Hashable, Sendable {
        nonisolated struct Point: Codable, Hashable, Sendable {
            let day: String
            let mastered: Int
        }

        let current: Int
        let total: Int
        let inProgress: Int
        let delta30: Int
        let series: [Point]
    }

    nonisolated struct Pattern: Codable, Hashable, Sendable, Identifiable {
        nonisolated enum Kind: String, Hashable, Sendable {
            case opening, time, late, hanging
        }

        /// What the pattern's row opens: its drill, the game to review, the games.
        nonisolated enum Action: String, Hashable, Sendable {
            case drill, review, games
        }

        let key: String
        let kind: Lenient<Kind>
        let title: String
        let detail: String
        let count: Int
        let positions: Int
        let action: Lenient<Action>
        let gameId: String?
        let cta: String

        var id: String { key }
    }

    nonisolated struct Goal: Codable, Hashable, Sendable {
        nonisolated struct Summary: Codable, Hashable, Sendable {
            let current: Int
            let goal: Int
            let distance: Int
            let delta30: Int?
            let paceLine: String?
            let reached: Bool
        }

        nonisolated struct Sample: Codable, Hashable, Sendable {
            let at: Date
            let rating: Int
        }

        let timeClass: String
        let set: Bool
        let suggested: Int
        let summary: Summary?
        let samples: [Sample]
    }

    let mastered: Mastered
    let patterns: [Pattern]
    var goal: Goal?
}

nonisolated struct ProgressPage: Codable, Hashable, Sendable {
    var day: String
    var streak: DailyStreak
    var line: String
    /// One cell per day, oldest first, 1 when a Daily 5 was finished; the last day is `day`.
    var calendar: [Int]
    var progress: HomeProgress
}

nonisolated struct PatternDrill: Codable, Hashable, Sendable {
    let key: String
    let title: String
    let detail: String
    let mistakes: [Mistake]
}

/// A position of a short session: a mistake from the player's games, or a
/// rated puzzle when nothing is due.
nonisolated struct TrainItem: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Hashable, Sendable {
        case mistake, puzzle, study
    }

    let id: String
    let kind: Lenient<Kind>
    let fen: String
    let bestUci: String
    let bestSan: String
    let label: String
    let classification: Lenient<MoveClass>?
    let moveLabel: String?
    let playedSan: String?
    let gameId: String?
    let firstTime: Bool
}

/// `GET /api/v1/daily`: today's positions, empty once the day's session is done.
nonisolated struct DailyPlan: Codable, Hashable, Sendable {
    var day: String
    var doneToday: Bool
    var source: Lenient<DailySource>?
    var items: [TrainItem]
    var streak: DailyStreak
    var line: String
}

nonisolated struct DailySessionRequest: Codable, Sendable {
    /// The device's IANA time zone: the server keeps the player's local day with it.
    let tz: String
    let source: DailySource
    let total: Int
}

nonisolated struct DailySessionStart: Codable, Hashable, Sendable {
    let alreadyDone: Bool
}

nonisolated struct DailyCompletionRequest: Codable, Sendable {
    let tz: String
    let source: DailySource
    let total: Int
    let solved: Int
}

nonisolated struct DailyCompletion: Codable, Hashable, Sendable {
    nonisolated struct Reminder: Codable, Hashable, Sendable {
        let channel: Lenient<ReminderChannel>
        let hour: Int?
    }

    /// False for a second session the same day: the streak did not move.
    let counted: Bool
    let streak: Int
    let longest: Int
    let freezes: Int
    let extended: Bool
    let freezeUsed: Int
    let earnedFreeze: Bool
    let sessionsDone: Int
    let reminder: Reminder
    /// Offer a reminder at this hour (shown once, after a session).
    let offerReminder: Bool
}

nonisolated struct ReminderRequest: Codable, Sendable {
    let channel: ReminderChannel
    let hour: Int?
    let tz: String?
}

nonisolated struct DailyReminder: Codable, Hashable, Sendable {
    let channel: Lenient<ReminderChannel>
    let hour: Int?
    let timezone: String?
}

nonisolated struct RatingGoalRequest: Codable, Sendable {
    /// Nil clears the goal; the key is always sent, as the contract requires.
    let rating: Int?
    let timeClass: String?

    private enum CodingKeys: String, CodingKey { case rating, timeClass }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(timeClass, forKey: .timeClass)
    }
}

nonisolated struct RatingGoal: Codable, Hashable, Sendable {
    let rating: Int?
    let timeClass: String?
}

/// The time classes a rating goal can be set in, as the site's goal form offers them.
nonisolated enum TimeClass: String, CaseIterable, Identifiable, Sendable {
    case bullet, blitz, rapid, classical

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// "Blitz" for "blitz"; an unknown class keeps its own name.
    static func label(_ raw: String) -> String {
        TimeClass(rawValue: raw)?.label ?? raw
    }
}
