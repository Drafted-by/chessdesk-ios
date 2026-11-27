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
