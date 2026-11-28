import ChessCore
import SwiftUI

/// Training a repertoire, full screen: loads the session the server planned,
/// then runs its lines one after the other in the line trainer the opening
/// courses use.
struct RepertoireTrainerScreen: View {
    let request: RepertoireTrainingRequest

    @Environment(AppModel.self) private var app
    @Environment(NarrationPlayer.self) private var narration
    @Environment(\.dismiss) private var dismiss
    @State private var model: RepertoireTrainingModel?
    @State private var showsPremium = false

    var body: some View {
        Group {
            switch model?.phase {
            case nil, .loading:
                LoadingView()
            case let .failed(message):
                LoadFailureView(title: "This session did not load", message: message) {
                    Task { await model?.load() }
                }
            case let .premiumRequired(message):
                paywall(message)
            case let .ready(session):
                if let model { runner(model, session) }
            }
        }
        .overlay(alignment: .topLeading) { closeButton }
        .background(CD.canvas.ignoresSafeArea())
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
        .task {
            guard model == nil, let token = app.playerToken else { return }
            let fresh = RepertoireTrainingModel(request: request, app: app, token: token)
            model = fresh
            await fresh.load()
        }
        .onDisappear { narration.stop() }
    }

    @ViewBuilder private func runner(_ model: RepertoireTrainingModel, _ session: CourseSession) -> some View {
        if let item = model.current {
            LineTrainerView(
                line: item.line,
                side: item.line.learnerSide(deck: session.side),
                review: item.review,
                label: model.label,
                // Opened from a step of the plan, the repertoire is known by its id alone.
                chapter: request.name.isEmpty ? session.chapterTitles.first : request.name,
                narration: session.narration,
                following: model.hasNext ? .nextInSession : .none,
                onGrades: { grades in Task { await model.report(grades) } },
                onFollow: { if model.hasNext { model.advance() } else { close() } },
                close: close
            )
            .id(item.id)
        } else {
            LoadFailureView(
                title: session.mode == .review ? "Nothing to review" : "Nothing new to learn today",
                message: session.mode == .review
                    ? "Your lines are fresh. They come back here just before you would forget them."
                    : "You have learned today's lines, or the repertoire has no line yet. New lines are offered a few a day."
            )
        }
    }

    private func paywall(_ message: String) -> some View {
        VStack(spacing: CD.Space.s16) {
            CDBadge(text: "Premium", tone: .premium)
            Text(message)
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("See Premium") { showsPremium = true }
                .buttonStyle(.cd(.primary))
        }
        .padding(CD.Space.s32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
