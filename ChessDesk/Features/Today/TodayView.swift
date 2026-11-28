import SwiftUI

/// The first screen: what to do now. For a signed-in player, the reviews
/// that are due; for everyone, the course to continue or to start.
struct TodayView: View {
    let openCourses: () -> Void

    @Environment(AppModel.self) private var app

    private struct Content {
        let courses: [CourseCard]
        let due: DueSummary?
        /// The path put forward. Nil when the server does not serve paths yet.
        let path: PathCard?
    }

    /// Courses a newcomer can start with.
    private static let starters = ["first-1e4-repertoire", "practical-caro-kann", "practical-london-system"]

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(app.backend), AnyHashable(app.accountRevision)]),
            failureTitle: "Today did not load",
            load: load,
            content: { content in page(content) }
        )
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
    }

    private func load() async throws -> Content {
        let courses = try await app.api.courses(token: app.token)
        var due: DueSummary?
        if let token = app.token, app.isSignedIn {
            // Reviews are a bonus on this screen: without them it still works.
            due = try? await app.api.due(token: token)
        }
        // The featured course leads the screen, but Today works without it.
        let paths = try? await app.api.paths(token: app.token)
        return Content(courses: courses, due: due, path: paths?.first { $0.slug == FeaturedPath.slug })
    }

    private func page(_ content: Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Wordmark(size: 20)
                        .padding(.bottom, CD.Space.s24)
                    Text(greeting)
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "en_US"))))
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                }

                if let due = content.due, due.totalDue > 0 {
                    DueCard(due: due, courses: content.courses)
                }

                if let path = content.path {
                    FeaturedPathPlate(path: path, guest: app.isSignedIn ? nil : app.guestProgress)
                }

                if let current = currentCourse(content) {
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        SectionHeader(title: "Continue")
                        NavigationLink(value: CourseRoute.course(slug: current.slug)) {
                            CourseCardView(course: current)
                        }
                        .buttonStyle(CDPressStyle())
                    }
                } else if content.path == nil {
                    WelcomePlate(course: starter(content))
                }

                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    SectionHeader(
                        title: content.path == nil ? "Good places to start" : "Then, an opening of your own",
                        detail: "Complete repertoires. The first line of each is free."
                    )
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 330), spacing: CD.Space.s12, alignment: .top)],
                        spacing: CD.Space.s12
                    ) {
                        ForEach(starters(content)) { course in
                            NavigationLink(value: CourseRoute.course(slug: course.slug)) {
                                CourseCardView(course: course)
                            }
                            .buttonStyle(CDPressStyle())
                        }
                    }
                    Button(action: openCourses) {
                        HStack(spacing: CD.Space.s6) {
                            Text("All \(content.courses.count) courses")
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.cd(.ghost))
                    .padding(.leading, -10)
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: CD.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let words = hour < 5 ? "Good evening" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        guard let name = app.me?.user.name.split(separator: " ").first else { return words }
        return "\(words), \(name)"
    }

    private func currentCourse(_ content: Content) -> CourseCard? {
        let enrolled = content.courses.first { $0.enrollment == .active && ($0.progress?.learned ?? 0) > 0 }
        if let enrolled { return enrolled }
        guard let slug = app.guestProgress.lastCourse else { return nil }
        return content.courses.first { $0.slug == slug }
    }

    private func starters(_ content: Content) -> [CourseCard] {
        let current = currentCourse(content)?.slug
        return Self.starters
            .compactMap { slug in content.courses.first { $0.slug == slug } }
            .filter { $0.slug != current }
    }

    private func starter(_ content: Content) -> CourseCard? {
        content.courses.first { $0.slug == Self.starters[0] } ?? content.courses.first
    }
}

/// The lead plate for someone who has not started anything: says what the
/// app does and offers the one action.
private struct WelcomePlate: View {
    let course: CourseCard?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            let layout = sizeClass == .regular
                ? AnyLayout(HStackLayout(alignment: .center, spacing: CD.Space.s24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: CD.Space.s20))
            layout {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Learn an opening you will still know next month")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Each move comes with its reason. You play it on the board, then from memory, and it returns just before you would forget it.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let course {
                        NavigationLink(value: CourseRoute.course(slug: course.slug)) {
                            Text("Start with \(course.title)")
                        }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: sizeClass != .regular))
                        .padding(.top, CD.Space.s4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let course {
                    StaticBoardView(
                        fen: course.previewFen,
                        orientation: course.color.side,
                        highlight: course.previewHighlight,
                        cornerRadius: CD.Radius.md
                    )
                    .frame(maxWidth: sizeClass == .regular ? 260 : .infinity)
                }
            }
        }
    }
}

private struct DueCard: View {
    let due: DueSummary
    let courses: [CourseCard]

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text("Due for review")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                    HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                        Text(CDFormat.count(due.totalDue))
                            .cdFont(.metric)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        Text(due.totalDue == 1 ? "move" : "moves")
                            .cdFont(.body)
                            .foregroundStyle(CD.ink3)
                    }
                    .accessibilityElement(children: .combine)
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { CDHairline() }
                        switch row.target {
                        case let .course(slug):
                            NavigationLink(value: CourseRoute.course(slug: slug)) { label(row.deck) }
                                .buttonStyle(CDPressStyle())
                        case let .repertoire(request):
                            // A repertoire's review opens at once, in the trainer.
                            Button { review = request } label: { label(row.deck) }
                                .buttonStyle(CDPressStyle())
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $review) { RepertoireTrainerScreen(request: $0) }
    }

    @State private var review: RepertoireTrainingRequest?

    private func label(_ deck: DueSummary.Deck) -> some View {
        HStack {
            Text(deck.name)
                .cdFont(.bodyStrong)
                .foregroundStyle(CD.ink)
                .lineLimit(1)
            Spacer()
            Text(CDFormat.plural(deck.progress.dueLines, "line"))
                .cdFont(.small)
                .foregroundStyle(CD.accentStrong)
                .cdNumber()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var rows: [DueRow] { DueRow.rows(due: due, courses: courses) }
}

/// A deck with something due, and what its row opens: the page of a course,
/// or the review of one of the player's own repertoires.
struct DueRow {
    enum Target: Hashable {
        case course(slug: String)
        case repertoire(RepertoireTrainingRequest)
    }

    let deck: DueSummary.Deck
    let target: Target

    static func rows(due: DueSummary, courses: [CourseCard]) -> [DueRow] {
        due.decks.compactMap { deck in
            guard deck.progress.dueLines > 0 else { return nil }
            if let request = RepertoireTrainingRequest(deck: deck) {
                return DueRow(deck: deck, target: .repertoire(request))
            }
            guard deck.kind == "course", deck.deck.hasPrefix("course:") else { return nil }
            let slug = String(deck.deck.dropFirst("course:".count))
            return courses.contains { $0.slug == slug } ? DueRow(deck: deck, target: .course(slug: slug)) : nil
        }
    }
}
