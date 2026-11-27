import ChessCore
import Foundation

// The shapes of the ChessDesk app API (`/api/v1`). The contract is the
// OpenAPI file of the site, mirrored in `contracts/openapi-v1.json`; a test
// checks every model here against it. The API is additive: unknown fields
// are ignored, so a newer server never breaks an older app.

nonisolated struct APIUser: Codable, Hashable, Sendable {
    let id: String
    let email: String
    let name: String
    let role: String
    let emailVerified: Bool
}

nonisolated struct AuthSession: Codable, Hashable, Sendable {
    let token: String
    let expiresAt: Date
    let user: APIUser
}

nonisolated struct Me: Codable, Hashable, Sendable {
    struct Access: Codable, Hashable, Sendable {
        struct Trial: Codable, Hashable, Sendable {
            let status: String
            let endsAt: Date?
            let daysLeft: Int?
        }

        let premium: Bool
        let paid: Bool
        let viaCoachPlan: Bool
        let trial: Trial
    }

    struct FreeLimits: Codable, Hashable, Sendable {
        let repertoireLines: Int
        let explorerGames: Int
    }

    let user: APIUser
    /// False for an account created with Apple or Google. Nil from a server
    /// older than account creation in the app.
    let hasPassword: Bool?
    let access: Access
    let freeLimits: FreeLimits
}

nonisolated enum CourseColor: String, Codable, Hashable, Sendable {
    case white, black

    var side: Side { self == .white ? .white : .black }
}

nonisolated enum EnrollmentStatus: String, Codable, Hashable, Sendable {
    case active, archived
}

nonisolated struct DeckProgress: Codable, Hashable, Sendable {
    let lines: Int
    let learned: Int
    let newLines: Int
    let dueLines: Int
    let solidLines: Int
    let dueMoves: Int
    let moves: Int
}

nonisolated struct SquarePair: Codable, Hashable, Sendable {
    let from: String
    let to: String
}

nonisolated struct CourseTotals: Codable, Hashable, Sendable {
    let chapters: Int
    let lines: Int
    let moves: Int
}

nonisolated struct Narration: Codable, Hashable, Sendable {
    let base: String
    let keys: [String]
}

nonisolated struct CourseCard: Codable, Hashable, Identifiable, Sendable {
    let slug: String
    let title: String
    let color: CourseColor
    let style: [String]
    let level: String
    let description: String
    let totals: CourseTotals
    let previewFen: String
    let previewMove: SquarePair?
    let freeLineId: String
    let voiced: Bool
    let enrollment: EnrollmentStatus?
    let progress: DeckProgress?

    var id: String { slug }
}

nonisolated struct CoursesResponse: Codable, Hashable, Sendable {
    let courses: [CourseCard]
}

nonisolated enum LineState: String, Codable, Hashable, Sendable {
    case new, learning, due, solid, locked
}

nonisolated struct CourseDetail: Codable, Hashable, Sendable {
    struct Chapter: Codable, Hashable, Sendable {
        struct Line: Codable, Hashable, Identifiable, Sendable {
            let id: String
            let label: String
            let moves: Int
            let state: LineState
            let free: Bool
        }

        let title: String
        let intro: String?
        let lines: [Line]
    }

    struct Pace: Codable, Hashable, Sendable {
        let perDay: Int
        let newLeft: Int
    }

    let slug: String
    let title: String
    let color: CourseColor
    let style: [String]
    let level: String
    let description: String
    let totals: CourseTotals
    let previewFen: String
    let previewMove: SquarePair?
    let freeLineId: String
    let voiced: Bool
    let enrollment: EnrollmentStatus?
    let intro: String
    let deck: String
    let progress: DeckProgress
    let chapters: [Chapter]
    let pace: Pace
    let freeLearned: Bool
    let narration: Narration?
}

nonisolated struct LineStep: Codable, Hashable, Sendable {
    struct Shape: Codable, Hashable, Sendable {
        let brush: String
        let orig: String
        let dest: String?
    }

    let san: String
    let uci: String
    let fenBefore: String
    let fenAfter: String
    let key: String
    let mine: Bool
    let comments: [String]
    let shapes: [Shape]
    let ply: Int
}

nonisolated struct TrainingLine: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let chapter: Int
    let index: Int
    let startFen: String
    let steps: [LineStep]
    /// The side the learner plays in this line, when it is not the deck's.
    let side: String?

    func learnerSide(deck: Side) -> Side {
        switch side {
        case "WHITE": .white
        case "BLACK": .black
        default: deck
        }
    }
}

nonisolated enum SessionMode: String, Codable, Hashable, Sendable {
    case learn, review
}

nonisolated struct CourseSession: Codable, Hashable, Sendable {
    struct ReviewItem: Codable, Hashable, Sendable {
        let lineId: String
        let test: [Int]
    }

    struct NextLine: Codable, Hashable, Sendable {
        let lineId: String
        let locked: Bool
    }

    let deck: String
    let mode: SessionMode
    let color: String
    let lines: [TrainingLine]
    let learn: [String]
    let review: [ReviewItem]
    let known: [String]
    let next: NextLine?
    let chapterTitles: [String]
    let narration: Narration?

    var side: Side { color == "BLACK" ? .black : .white }
}

nonisolated struct MoveGrade: Codable, Hashable, Sendable {
    enum Grade: String, Codable, Hashable, Sendable {
        case again, good
    }

    let fen: String
    let uci: String
    let grade: Grade
}

nonisolated struct DueSummary: Codable, Hashable, Sendable {
    struct Deck: Codable, Hashable, Sendable {
        let deck: String
        let kind: String
        let name: String
        let color: String
        let progress: DeckProgress
    }

    struct LearnNext: Codable, Hashable, Sendable {
        let deck: String
        let newLeftToday: Int
    }

    let totalDue: Int
    let decks: [Deck]
    let top: String?
    let learnNext: LearnNext?
}

nonisolated struct LocalProgressResult: Codable, Hashable, Sendable {
    let imported: Int
}

nonisolated struct OkResponse: Codable, Hashable, Sendable {
    let ok: Bool?
}

// MARK: Requests

nonisolated struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

nonisolated struct SignupRequest: Codable, Sendable {
    let firstName: String
    let lastName: String
    let email: String
    let password: String
}

nonisolated struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    /// Apple gives the name once, at the first authorisation.
    let firstName: String?
    let lastName: String?
}

nonisolated struct DeleteAccountRequest: Codable, Sendable {
    let currentPassword: String?
    let appleAuthorizationCode: String?
}

nonisolated struct GradesRequest: Codable, Sendable {
    let deck: String
    let grades: [MoveGrade]
}

nonisolated struct LocalProgressRequest: Codable, Sendable {
    let grades: [MoveGrade]
}

nonisolated struct EnrollmentRequest: Codable, Sendable {
    let status: EnrollmentStatus
}

// MARK: Errors

/// The API's single error shape: `{ "error": { "code", "message" } }`.
nonisolated struct APIErrorBody: Codable, Sendable {
    struct Detail: Codable, Sendable {
        let code: String
        let message: String
    }

    let error: Detail
}

nonisolated enum APIError: Error, Equatable, Sendable {
    /// The server answered with its error shape.
    case server(status: Int, code: String, message: String)
    /// No answer: offline, timeout, DNS.
    case offline
    /// An answer the app could not read.
    case unreadable

    var code: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
    }

    var isUnauthorized: Bool { code == "unauthorized" }
    var isPremiumRequired: Bool { code == "premium_required" }
    var isEmailTaken: Bool { code == "email_taken" }

    /// A sentence for the player. Server messages are already written for them.
    var message: String {
        switch self {
        case let .server(_, _, message): message
        case .offline: "ChessDesk could not be reached. Check your connection and try again."
        case .unreadable: "ChessDesk sent an answer this version of the app cannot read."
        }
    }
}

// MARK: Learning paths

nonisolated enum StageState: String, Codable, Hashable, Sendable {
    case locked, new, started, done
}

nonisolated struct PathNext: Codable, Hashable, Sendable {
    let stage: String
    let title: String
    let locked: Bool
}

nonisolated struct PathTotals: Codable, Hashable, Sendable {
    let modules: Int
    let stages: Int
    let exercises: Int
}

nonisolated struct PathCard: Codable, Hashable, Identifiable, Sendable {
    let slug: String
    let title: String
    let level: String
    let description: String
    let color: CourseColor
    let previewFen: String
    let totals: PathTotals
    let learned: Int
    let voiced: Bool
    let next: PathNext?

    var id: String { slug }
}

nonisolated struct PathsResponse: Codable, Hashable, Sendable {
    let paths: [PathCard]
}

nonisolated struct PathDetail: Codable, Hashable, Sendable {
    struct Stage: Codable, Hashable, Identifiable, Sendable {
        let slug: String
        let title: String
        let free: Bool
        let state: StageState
        let exercises: Int
        let learned: Int
        let courses: [String]
        let closing: Bool

        var id: String { slug }
    }

    struct Module: Codable, Hashable, Identifiable, Sendable {
        let slug: String
        let title: String
        let summary: String
        let free: Bool
        let locked: Bool
        let board: String?
        let exercises: Int
        let learned: Int
        let stages: [Stage]

        var id: String { slug }
    }

    struct Introduction: Codable, Hashable, Sendable {
        let title: String
        let summary: String
        let segments: [String]
    }

    let slug: String
    let title: String
    let level: String
    let description: String
    let color: CourseColor
    let previewFen: String
    let totals: PathTotals
    let learned: Int
    let voiced: Bool
    let next: PathNext?
    let intro: String
    let deck: String
    let modules: [Module]
    let introduction: Introduction?
    let narration: Narration?

    var stages: [Stage] { modules.flatMap(\.stages) }
}

/// How an exercise of a path is worked. `lesson`: played once with the
/// explanation of each move. `solve`: a position where the learner finds the
/// moves. `learn`: the way of the opening courses, guided then from memory.
nonisolated enum ExerciseFlow: String, Codable, Hashable, Sendable {
    case learn, lesson, solve
}

nonisolated struct PathSession: Codable, Hashable, Sendable {
    struct Stage: Codable, Hashable, Sendable {
        let slug: String
        let title: String
        let module: String
        let number: Int
        let of: Int
    }

    struct Exercise: Codable, Hashable, Sendable {
        let lineId: String
        let title: String
        let flow: ExerciseFlow
        let task: String?
        let aid: String?
    }

    let deck: String
    let color: String
    let stage: Stage
    let lines: [TrainingLine]
    let learn: [String]
    let replay: Bool
    let known: [String]
    let exercises: [Exercise]
    let next: PathNext?
    let courses: [String]
    let closing: Bool
    let narration: Narration?

    var side: Side { color == "BLACK" ? .black : .white }
}
