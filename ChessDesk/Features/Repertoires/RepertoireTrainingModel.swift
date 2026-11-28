import Foundation
import Observation

/// What to train: a repertoire, and Learn or Review. Without a mode the
/// server chooses: the review when moves are due, else Learn.
struct RepertoireTrainingRequest: Identifiable, Hashable {
    let id: String
    let name: String
    var mode: SessionMode?

    /// The deck of the due summary is "repertoire:<id>".
    init?(deck: DueSummary.Deck) {
        let prefix = "repertoire:"
        guard deck.kind == "repertoire", deck.deck.hasPrefix(prefix), deck.deck.count > prefix.count else { return nil }
        id = String(deck.deck.dropFirst(prefix.count))
        name = deck.name
        mode = .review
    }

    init(id: String, name: String, mode: SessionMode? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
    }
}

/// One training session of a repertoire. A repertoire is a deck like a
/// course: its session has the shape of a course session and is run by the
/// same line trainer; the grades go to `POST /training/grades` with the deck
/// the session names.
@Observable
final class RepertoireTrainingModel {
    enum Phase: Equatable {
        case loading
        case ready(CourseSession)
        case failed(String)
        /// The free plan trains the first repertoire only.
        case premiumRequired(String)
    }

    /// A line of the session, with the steps to test when it is a review.
    struct Item: Identifiable, Hashable {
        let line: TrainingLine
        let review: [Int]?

        var id: String { line.id }
    }

    let request: RepertoireTrainingRequest
    private(set) var phase: Phase = .loading
    private(set) var index = 0
    /// Grades the server has not taken yet: they go out with the next ones.
    private(set) var unsent: [MoveGrade] = []

    private let loadSession: @Sendable (String, SessionMode?) async throws -> CourseSession
    private let sendGrades: @Sendable (String, [MoveGrade]) async throws -> Void
    private let onUnauthorized: () -> Void

    init(
        request: RepertoireTrainingRequest,
        loadSession: @escaping @Sendable (String, SessionMode?) async throws -> CourseSession,
        sendGrades: @escaping @Sendable (String, [MoveGrade]) async throws -> Void,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.request = request
        self.loadSession = loadSession
        self.sendGrades = sendGrades
        self.onUnauthorized = onUnauthorized
    }

    convenience init(request: RepertoireTrainingRequest, app: AppModel, token: String) {
        let api = app.api
        self.init(
            request: request,
            loadSession: { id, mode in try await api.repertoireSession(id: id, mode: mode, token: token) },
            sendGrades: { deck, grades in try await api.sendGrades(deck: deck, grades: grades, token: token) },
            onUnauthorized: { [weak app] in app?.sessionExpired() }
        )
    }

    var session: CourseSession? {
        if case let .ready(session) = phase { return session }
        return nil
    }

    /// The lines to work, in the order the server planned them.
    var items: [Item] {
        guard let session else { return [] }
        return Self.items(of: session)
    }

    static func items(of session: CourseSession) -> [Item] {
        let lines = Dictionary(session.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        switch session.mode {
        case .learn: return session.learn.compactMap { id in lines[id].map { Item(line: $0, review: nil) } }
        case .review: return session.review.compactMap { item in lines[item.lineId].map { Item(line: $0, review: item.test) } }
        }
    }

    var current: Item? {
        let items = items
        return items.isEmpty ? nil : items[min(index, items.count - 1)]
    }

    var hasNext: Bool { index + 1 < items.count }

    var label: String {
        guard let session else { return "" }
        let count = items.count
        if session.mode == .review { return "Review · \(index + 1) of \(count)" }
        return count > 1 ? "New line \(index + 1) of \(count)" : "New line"
    }

    func load() async {
        do {
            phase = .ready(try await loadSession(request.id, request.mode))
            index = 0
        } catch is CancellationError {
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            phase = failure.isPremiumRequired ? .premiumRequired(failure.message) : .failed(failure.message)
        }
    }

    func advance() {
        if hasNext { index += 1 }
    }

    /// Sends the grades of a finished line, with any the server missed before.
    func report(_ grades: [MoveGrade]) async {
        guard let session else { return }
        let batch = unsent + grades
        guard !batch.isEmpty else { return }
        unsent = []
        do {
            try await sendGrades(session.deck, batch)
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized {
                onUnauthorized()
            } else if failure.isPremiumRequired {
                // The server will not take them: nothing to try again.
            } else {
                unsent = batch
            }
        }
    }
}
