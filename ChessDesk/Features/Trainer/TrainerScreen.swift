import ChessCore
import SwiftUI

/// What to train: a course, learn or review, and optionally one chosen line.
struct TrainerRequest: Identifiable, Hashable {
    let slug: String
    let courseTitle: String
    let freeLineId: String
    let mode: SessionMode
    var line: String?

    var id: String { "\(slug)|\(mode.rawValue)|\(line ?? "")" }

    init(course: CourseDetail, mode: SessionMode, line: String?) {
        slug = course.slug
        courseTitle = course.title
        freeLineId = course.freeLineId
        self.mode = mode
        self.line = line
    }
}

/// The full-screen trainer: loads the session, then runs its lines one
/// after the other.
struct TrainerScreen: View {
    @State var request: TrainerRequest

    @Environment(AppModel.self) private var app
    @Environment(NarrationPlayer.self) private var narration
    @Environment(\.dismiss) private var dismiss
    @State private var showsPremium = false

    var body: some View {
        Loadable(
            id: AnyHashable(request),
            failureTitle: request.mode == .review ? "Your review did not load" : "This line did not load",
            load: {
                try await app.api.courseSession(
                    slug: request.slug, mode: request.mode, line: request.line, token: app.token
                )
            },
            content: { session in
                SessionRunner(
                    request: request,
                    session: session,
                    close: close,
                    openLine: { request.line = $0 },
                    showPremium: { showsPremium = true }
                )
                .id(request)
            }
        )
        .overlay(alignment: .topLeading) { closeButton }
        .background(CD.canvas.ignoresSafeArea())
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
        .onDisappear { narration.stop() }
    }

    private func close() {
        narration.stop()
        dismiss()
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CD.ink2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
        .padding(.leading, CD.Space.s4)
    }
}

/// Runs the lines of one session in order and reports the grades: to the
/// account when signed in, to the device for a guest.
private struct SessionRunner: View {
    let request: TrainerRequest
    let session: CourseSession
    let close: () -> Void
    let openLine: (String) -> Void
    let showPremium: () -> Void

    @Environment(AppModel.self) private var app
    @State private var index = 0

    private struct Item: Identifiable {
        let line: TrainingLine
        let review: [Int]?
        var id: String { line.id }
    }

    private var items: [Item] {
        let byID = Dictionary(uniqueKeysWithValues: session.lines.map { ($0.id, $0) })
        switch session.mode {
        case .learn:
            return session.learn.compactMap { id in byID[id].map { Item(line: $0, review: nil) } }
        case .review:
            return session.review.compactMap { item in byID[item.lineId].map { Item(line: $0, review: item.test) } }
        }
    }

    var body: some View {
        let items = items
        if items.isEmpty {
            LoadFailureView(
                title: session.mode == .review ? "Nothing to review" : "Nothing new to learn today",
                message: session.mode == .review
                    ? "Your lines are fresh. They come back here just before you would forget them."
                    : "You have learned today's lines. Come back tomorrow for the next ones."
            )
        } else {
            let item = items[min(index, items.count - 1)]
            LineTrainerView(
                line: item.line,
                side: session.side,
                review: item.review,
                label: label(index: index, count: items.count),
                chapter: chapterTitle(item.line),
                narration: session.narration,
                following: following(after: index, count: items.count),
                onGrades: report,
                onFollow: { follow(index: index, count: items.count) },
                close: close
            )
            .id(item.id)
        }
    }

    private func label(index: Int, count: Int) -> String {
        if session.mode == .review { return "Review · \(index + 1) of \(count)" }
        if count > 1 { return "Today · line \(index + 1) of \(count)" }
        return request.line == request.freeLineId ? "Your free line" : "Chosen line"
    }

    private func chapterTitle(_ line: TrainingLine) -> String? {
        session.chapterTitles.indices.contains(line.chapter) ? session.chapterTitles[line.chapter] : nil
    }

    private func following(after index: Int, count: Int) -> LineTrainerView.Following {
        if index + 1 < count { return .nextInSession }
        guard let next = session.next else { return .none }
        return next.locked ? .locked : .nextLine
    }

    private func follow(index: Int, count: Int) {
        if index + 1 < count {
            self.index = index + 1
        } else if let next = session.next {
            if next.locked { showPremium() } else { openLine(next.lineId) }
        } else {
            close()
        }
    }

    private func report(_ grades: [MoveGrade]) {
        guard !grades.isEmpty else { return }
        guard let token = app.token, app.isSignedIn else {
            app.recordGuestGrades(grades, course: request.slug)
            return
        }
        Task {
            do {
                try await app.api.sendGrades(deck: session.deck, grades: grades, token: token)
            } catch let error as APIError where error.isUnauthorized {
                // Signed out elsewhere: keep the work on the device.
                app.recordGuestGrades(grades, course: request.slug)
                app.sessionExpired()
            } catch {
                app.recordGuestGrades(grades, course: request.slug)
            }
        }
    }
}
