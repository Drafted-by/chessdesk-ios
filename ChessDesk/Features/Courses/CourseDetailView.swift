import ChessCore
import SwiftUI

/// One course: what it teaches, where the learner stands, its chapters and
/// lines. The lead action starts or continues learning.
struct CourseDetailView: View {
    let slug: String

    @Environment(AppModel.self) private var app
    @State private var trainer: TrainerRequest?
    @State private var showsPremium = false
    @State private var reload = 0

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(slug), AnyHashable(app.backend), AnyHashable(app.accountRevision), AnyHashable(reload)]),
            failureTitle: "This course did not load",
            load: { try await app.api.course(slug: slug, token: app.token) },
            content: { course in
                page(course)
                #if DEBUG
                    .onAppear {
                        if DebugLaunch.opensTrainer, trainer == nil, reload == 0 {
                            trainer = TrainerRequest(course: course, mode: .learn, line: course.freeLineId)
                        }
                    }
                #endif
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
        .onAppear { app.noteCourseOpened(slug) }
        .fullScreenCover(item: $trainer, onDismiss: { reload += 1 }) { request in
            TrainerScreen(request: request)
        }
        .sheet(isPresented: $showsPremium) {
            PremiumSheet()
        }
    }

    private func page(_ course: CourseDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                CourseHero(course: course, lead: leadAction(course)) { action in
                    run(action, course)
                }
                CourseFacts(course: course)
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    SectionHeader(title: "About this course")
                    Text(course.intro)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .frame(maxWidth: CD.readingWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: CD.Space.s24) {
                    SectionHeader(
                        title: "Chapters",
                        detail: "\(CDFormat.plural(course.totals.chapters, "chapter")), \(CDFormat.plural(course.totals.lines, "line"))"
                    )
                    ForEach(Array(course.chapters.enumerated()), id: \.offset) { index, chapter in
                        ChapterSection(number: index + 1, chapter: chapter) { line in
                            if line.state == .locked {
                                showsPremium = true
                            } else {
                                trainer = TrainerRequest(course: course, mode: .learn, line: line.id)
                            }
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Lead action

    enum LeadAction: Equatable {
        case startFree
        case practiseFree
        case learn(newToday: Int)
        case review(due: Int)

        var title: String {
            switch self {
            case .startFree: "Start your free line"
            case .practiseFree: "Practise your free line"
            case .learn: "Learn the next line"
            case let .review(due): "Review \(CDFormat.plural(due, "line"))"
            }
        }
    }

    private func leadAction(_ course: CourseDetail) -> LeadAction {
        if course.progress.dueLines > 0, app.isSignedIn { return .review(due: course.progress.dueLines) }
        if app.hasPremium, course.pace.newLeft > 0, course.progress.newLines > 0 {
            return .learn(newToday: course.pace.newLeft)
        }
        let learnedHere = course.freeLearned || app.guestProgress.learnedMoves(course: slug) > 0
        return learnedHere ? .practiseFree : .startFree
    }

    private func run(_ action: LeadAction, _ course: CourseDetail) {
        switch action {
        case .startFree, .practiseFree:
            trainer = TrainerRequest(course: course, mode: .learn, line: course.freeLineId)
        case .learn:
            trainer = TrainerRequest(course: course, mode: .learn, line: nil)
        case .review:
            trainer = TrainerRequest(course: course, mode: .review, line: nil)
        }
    }
}

// MARK: Hero

private struct CourseHero: View {
    let course: CourseDetail
    let lead: CourseDetailView.LeadAction
    let run: (CourseDetailView.LeadAction) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .center, spacing: CD.Space.s32) {
                board.frame(width: 300, height: 300)
                copy
            }
        } else {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                copy
                board.frame(maxWidth: .infinity)
            }
        }
    }

    private var board: some View {
        StaticBoardView(
            fen: course.previewFen,
            orientation: course.color.side,
            highlight: highlight,
            cornerRadius: CD.Radius.md
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }

    private var highlight: (from: Square, to: Square)? {
        guard let move = course.previewMove, let from = Square(move.from), let to = Square(move.to) else { return nil }
        return (from, to)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                HStack(spacing: CD.Space.s6) {
                    SideSwatch(side: course.color.side)
                    Text("\(course.color == .white ? "White" : "Black") · \(course.level)")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                }
                Text(course.title)
                    .cdFont(.pageTitle)
                    .foregroundStyle(CD.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(course.description)
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Button(lead.title) { run(lead) }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                Text(caption)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private var caption: String {
        switch lead {
        case .startFree: "Free, no account needed. About five minutes."
        case .practiseFree: "Play it again from memory, or learn it once more."
        case let .learn(newToday): "\(CDFormat.plural(newToday, "new line")) left today."
        case .review: "Lines come back just before you would forget them."
        }
    }
}

private struct CourseFacts: View {
    let course: CourseDetail

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            fact(CDFormat.count(course.totals.lines), "lines")
            divider
            fact(CDFormat.count(course.totals.moves), "moves to learn")
            divider
            fact(course.voiced ? "Voiced" : "Text", course.voiced ? "notes read aloud" : "notes on every move")
        }
        .padding(.vertical, CD.Space.s16)
        .cardSurface()
        .hairline()
    }

    private var divider: some View {
        Rectangle().fill(CD.line).frame(width: 1, height: 40)
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: CD.Space.s4) {
            Text(value)
                .cdFont(.metricMedium)
                .foregroundStyle(CD.ink)
                .cdNumber()
            Text(label)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CD.Space.s8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Chapters

private struct ChapterSection: View {
    let number: Int
    let chapter: CourseDetail.Chapter
    let open: (CourseDetail.Chapter.Line) -> Void

    @State private var expanded = false
    private let collapsedCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s12) {
                Text("\(number)")
                    .font(.custom("Newsreader72pt-Italic", size: 26, relativeTo: .title2))
                    .foregroundStyle(CD.ink4)
                    .cdNumber()
                    .frame(minWidth: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text(chapter.title)
                        .cdFont(.serifCard)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let intro = chapter.intro, !intro.isEmpty {
                        Text(intro)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .lineLimit(expanded ? nil : 3)
                    }
                }
            }

            VStack(spacing: 0) {
                let lines = expanded ? chapter.lines : Array(chapter.lines.prefix(collapsedCount))
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { CDHairline() }
                    Button { open(line) } label: { LineRow(line: line) }
                        .buttonStyle(CDPressStyle())
                }
                if chapter.lines.count > collapsedCount {
                    CDHairline()
                    Button {
                        withAnimation(CD.Motion.enter) { expanded.toggle() }
                    } label: {
                        HStack {
                            Text(expanded ? "Show fewer" : "All \(chapter.lines.count) lines")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink2)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CD.ink4)
                        }
                        .padding(.horizontal, CD.Space.s16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CDPressStyle())
                }
            }
            .cardSurface()
            .hairline()
        }
    }
}

private struct LineRow: View {
    let line: CourseDetail.Chapter.Line

    var body: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                Text(line.label)
                    .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(line.state == .locked ? CD.ink3 : CD.ink)
                    .cdNumber()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .cdFont(.meta)
                    .foregroundStyle(stateColor)
                    .cdNumber()
            }
            Spacer(minLength: CD.Space.s8)
            if line.state == .locked {
                Image(systemName: "lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CD.ink3)
                    .accessibilityLabel("Premium")
            } else {
                if line.free { CDBadge(text: "Free", tone: .accent) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CD.ink4)
            }
        }
        .padding(.horizontal, CD.Space.s16)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var detail: String {
        let moves = CDFormat.plural(line.moves, "move")
        return switch line.state {
        case .new, .locked: moves
        case .learning: "\(moves) · learning"
        case .due: "\(moves) · due for review"
        case .solid: "\(moves) · learned"
        }
    }

    private var stateColor: Color {
        switch line.state {
        case .due: CD.accentStrong
        case .solid: CD.win
        default: CD.ink3
        }
    }
}
