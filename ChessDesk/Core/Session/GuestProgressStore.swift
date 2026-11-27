import Foundation

/// What a guest has done, kept on the device: the grades of the moves they
/// practised, per course. When they create or open an account, the grades go
/// to the server (`POST /courses/{slug}/local-progress`) and the file is
/// cleared, so nothing learned before signing in is lost.
nonisolated struct GuestProgress: Codable, Equatable, Sendable {
    /// Grades by course slug, latest grade last. One entry per move.
    var grades: [String: [MoveGrade]] = [:]
    /// The last course opened, to offer "Continue" on Today.
    var lastCourse: String?
    /// Stages of a learning path finished on this device, by path slug.
    var completedStages: [String: [String]] = [:]

    init() {}

    /// Files written by an earlier build have fewer keys: every key is optional.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grades = try container.decodeIfPresent([String: [MoveGrade]].self, forKey: .grades) ?? [:]
        lastCourse = try container.decodeIfPresent(String.self, forKey: .lastCourse)
        completedStages = try container.decodeIfPresent([String: [String]].self, forKey: .completedStages) ?? [:]
    }

    /// Grades of a learning path are kept apart from those of a course of the
    /// same slug, and go to the account through the path's own route.
    static func pathKey(_ slug: String) -> String { "path:\(slug)" }

    func hasCompleted(stage: String, path: String) -> Bool {
        completedStages[path]?.contains(stage) ?? false
    }

    mutating func complete(stage: String, path: String) {
        guard !hasCompleted(stage: stage, path: path) else { return }
        completedStages[path, default: []].append(stage)
    }

    mutating func record(_ new: [MoveGrade], course: String) {
        var merged = grades[course] ?? []
        for grade in new {
            merged.removeAll { $0.fen == grade.fen && $0.uci == grade.uci }
            merged.append(grade)
        }
        grades[course] = merged
    }

    func learnedMoves(course: String) -> Int {
        grades[course]?.count { $0.grade == .good } ?? 0
    }
}

nonisolated struct GuestProgressStore: Sendable {
    let url: URL

    static var standard: GuestProgressStore {
        let folder = URL.applicationSupportDirectory.appending(path: "ChessDesk", directoryHint: .isDirectory)
        return GuestProgressStore(url: folder.appending(path: "guest-progress.json"))
    }

    func load() -> GuestProgress {
        guard let data = try? Data(contentsOf: url),
              let progress = try? JSONDecoder().decode(GuestProgress.self, from: data)
        else { return GuestProgress() }
        return progress
    }

    func save(_ progress: GuestProgress) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(progress).write(to: url, options: .atomic)
        } catch {
            // Losing guest progress is not worth interrupting a lesson for;
            // the next save tries again.
        }
    }
}
