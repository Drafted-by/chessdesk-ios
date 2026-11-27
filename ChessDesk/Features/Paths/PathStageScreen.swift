import ChessCore
import SwiftUI

/// One stage of a learning path to work.
struct StageRequest: Identifiable, Hashable {
    let path: String
    let pathTitle: String
    var stage: String

    var id: String { "\(path)|\(stage)" }
}

/// The full-screen trainer of a stage: its exercises one after the other,
/// then where the stage leads.
struct PathStageScreen: View {
    @State var request: StageRequest
    let showPremium: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(NarrationPlayer.self) private var narration
    @Environment(\.dismiss) private var dismiss
    @State private var premiumMessage: String?

    var body: some View {
        Group {
            if let premiumMessage {
                StagePaywall(message: premiumMessage, close: close) {
                    close()
                    showPremium()
                }
            } else {
                Loadable(
                    id: AnyHashable(request),
                    failureTitle: "This stage did not load",
                    load: load,
                    content: { session in
                        if let session {
                            StageRunner(request: request, session: session, close: close) { next in
                                if next.locked {
                                    premiumMessage = "\(next.title) is part of Premium."
                                } else {
                                    request.stage = next.stage
                                }
                            }
                            .id(request)
                        }
                    }
                )
            }
        }
        .overlay(alignment: .topLeading) {
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
        .background(CD.canvas.ignoresSafeArea())
        .onDisappear { narration.stop() }
    }

    /// The paywall is an answer of the server (403), not an error to retry.
    private func load() async throws -> PathSession? {
        do {
            return try await app.api.pathSession(slug: request.path, stage: request.stage, token: app.token)
        } catch let error as APIError where error.isPremiumRequired {
            premiumMessage = error.message
            return nil
        }
    }

    private func close() {
        narration.stop()
        dismiss()
    }
}

private struct StagePaywall: View {
    let message: String
    let close: () -> Void
    let seePremium: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s20) {
            Spacer()
            CDBadge(text: "Premium", tone: .premium)
            Text(message)
                .cdFont(.pageTitle)
                .foregroundStyle(CD.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("The free stages show how the course works. Premium opens every stage, and every opening course.")
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("See Premium", action: seePremium)
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            Button("Back to the course", action: close)
                .buttonStyle(.cd(.ghost, fullWidth: true))
            Spacer()
        }
        .padding(CD.Space.s24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Runs the exercises of a stage and records what was done: grades to the
/// account when signed in, to the device for a guest.
private struct StageRunner: View {
    let request: StageRequest
    let session: PathSession
    let close: () -> Void
    let openNext: (PathNext) -> Void

    @Environment(AppModel.self) private var app
    @State private var index: Int
    @State private var finished = false

    init(request: StageRequest, session: PathSession, close: @escaping () -> Void, openNext: @escaping (PathNext) -> Void) {
        self.request = request
        self.session = session
        self.close = close
        self.openNext = openNext
        var start = 0
        #if DEBUG
            start = min(DebugLaunch.exercise, max(0, session.learn.count - 1))
        #endif
        _index = State(initialValue: start)
    }

    private struct Item: Identifiable {
        let line: TrainingLine
        let exercise: PathSession.Exercise
        var id: String { line.id }
    }

    private var items: [Item] {
        let lines = Dictionary(uniqueKeysWithValues: session.lines.map { ($0.id, $0) })
        let exercises = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.lineId, $0) })
        return session.learn.compactMap { id in
            guard let line = lines[id], let exercise = exercises[id] else { return nil }
            return Item(line: line, exercise: exercise)
        }
    }

    var body: some View {
        let items = items
        if finished || items.isEmpty {
            StageDone(session: session, close: close, openNext: openNext)
        } else {
            let item = items[min(index, items.count - 1)]
            let last = index + 1 >= items.count
            LineTrainerView(
                line: item.line,
                side: item.line.learnerSide(deck: session.side),
                review: nil,
                flow: item.exercise.flow,
                task: item.exercise.task,
                judge: app.judge,
                label: item.exercise.title,
                chapter: "\(session.stage.title) · \(index + 1) of \(items.count)",
                narration: session.narration,
                following: .nextInSession,
                followTitle: last ? "Finish the stage" : "Next exercise",
                onGrades: report,
                onFollow: {
                    if last { finish() } else { index += 1 }
                },
                close: close
            )
            .id(item.id)
        }
    }

    private func finish() {
        if !app.isSignedIn { app.recordGuestStage(session.stage.slug, path: request.path) }
        finished = true
    }

    private func report(_ grades: [MoveGrade]) {
        guard !grades.isEmpty else { return }
        let localKey = GuestProgress.pathKey(request.path)
        guard let token = app.token, app.isSignedIn else {
            app.recordGuestGrades(grades, course: localKey)
            return
        }
        Task {
            do {
                try await app.api.sendGrades(deck: session.deck, grades: grades, token: token)
            } catch let error as APIError where error.isUnauthorized {
                app.recordGuestGrades(grades, course: localKey)
                app.sessionExpired()
            } catch {
                app.recordGuestGrades(grades, course: localKey)
            }
        }
    }
}

/// The end of a stage: what was done, and the stage that follows.
private struct StageDone: View {
    let session: PathSession
    let close: () -> Void
    let openNext: (PathNext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s20) {
            Spacer()
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text("Stage \(session.stage.number) of \(session.stage.of) · \(session.stage.module)")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                Text("\(session.stage.title): done")
                    .cdFont(.display)
                    .foregroundStyle(CD.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("\(CDFormat.plural(session.learn.count, "exercise")) worked. The patterns come back in later stages, in new positions.")
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OrnamentRule()
            if let next = session.next {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Next: \(next.title)")
                        .cdFont(.serifCard)
                        .foregroundStyle(CD.ink)
                    Button {
                        openNext(next)
                    } label: {
                        if next.locked {
                            Label("Next stage", systemImage: "lock")
                        } else {
                            Text("Next stage")
                        }
                    }
                    .buttonStyle(.cd(next.locked ? .secondary : .primary, size: .large, fullWidth: true))
                }
            }
            Button("Back to the course", action: close)
                .buttonStyle(.cd(session.next == nil ? .primary : .ghost, size: .large, fullWidth: true))
            Spacer()
        }
        .padding(CD.Space.s24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
