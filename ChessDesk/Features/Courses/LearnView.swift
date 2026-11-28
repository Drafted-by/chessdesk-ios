import ChessCore
import SwiftUI

/// "Learn": the player's own repertoires, the learning path, and the
/// catalogue of opening courses. Open to guests: the first line of every
/// course is free; the repertoires say what an account brings.
struct LearnView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: CourseFilter = .all
    @State private var revisits = 0
    @State private var hasAppeared = false

    enum CourseFilter: Hashable {
        case all, white, black
    }

    private struct Content {
        let courses: [CourseCard]
        let path: PathCard?
        /// The player's repertoires; nil for a guest, or when they did not load.
        let repertoires: RepertoireList?
    }

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(app.backend), AnyHashable(app.accountRevision), AnyHashable(revisits)]),
            failureTitle: "Learn did not load",
            load: {
                // The path and the repertoires are extras: the catalogue shows without them.
                async let paths = try? app.api.paths(token: app.token)
                async let repertoires = repertoires()
                let courses = try await app.api.courses(token: app.token)
                return Content(
                    courses: courses, path: await paths?.first { $0.slug == FeaturedPath.slug }, repertoires: await repertoires
                )
            },
            content: { content in catalogue(content) }
        )
        .navigationTitle("Learn")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
    }

    private func repertoires() async -> RepertoireList? {
        guard let token = app.playerToken else { return nil }
        return try? await app.api.repertoires(token: token)
    }

    private func catalogue(_ content: Content) -> some View {
        let courses = content.courses
        let path = content.path
        let shown = courses.filter { course in
            switch filter {
            case .all: true
            case .white: course.color == .white
            case .black: course.color == .black
            }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                Text("Learn")
                    .cdFont(.display)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)

                MyRepertoiresRow(list: content.repertoires, isSignedIn: app.isSignedIn)

                if let path {
                    PathBanner(path: path)
                }

                SectionHeader(
                    title: "Opening courses",
                    detail: "Complete repertoires, taught move by move. The first line of every course is free."
                )
                .padding(.top, CD.Space.s8)

                CDSegmented(
                    options: [
                        (.all, "All \(courses.count)"),
                        (.white, "As White"),
                        (.black, "As Black"),
                    ],
                    selection: $filter
                )
                .frame(maxWidth: 420)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330), spacing: CD.Space.s12, alignment: .top)],
                    spacing: CD.Space.s12
                ) {
                    ForEach(shown) { course in
                        NavigationLink(value: CourseRoute.course(slug: course.slug)) {
                            CourseCardView(course: course)
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s24)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: CD.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        // Back from a trainer or from the repertoires, a signed-in player's
        // progress has moved: read again, behind what is shown. The first
        // appearance is the load itself.
        .onAppear {
            guard app.isSignedIn else { return }
            if hasAppeared { revisits += 1 } else { hasAppeared = true }
        }
    }
}

/// The way to the player's own repertoires, on top of Learn. A row of a
/// working screen: what it is, and its state when the server gave one. For a
/// guest it says what a repertoire is; the screen it opens offers the account.
private struct MyRepertoiresRow: View {
    let list: RepertoireList?
    let isSignedIn: Bool

    var body: some View {
        NavigationLink(value: AppRoute.repertoires) {
            FeatureRow(
                emblem: .repertoire,
                title: "My repertoires",
                detail: detail,
                figure: (list?.totalDue).flatMap { $0 > 0 ? .init(value: CDFormat.count($0), caption: "due", isDue: true) : nil }
            )
            .cardSurface()
            .hairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard isSignedIn else { return "The openings you choose to play, built move by move and trained. With a free account." }
        guard let list else { return "The openings you choose to play, built move by move and trained." }
        if list.repertoires.isEmpty { return "Build your first one: pick your moves, prepare an answer to every reply." }
        let moves = list.repertoires.reduce(0) { $0 + $1.moves }
        return "\(CDFormat.plural(list.repertoires.count, "repertoire")) · \(CDFormat.plural(moves, "move"))"
    }
}

/// The featured path above the catalogue: quiet here (Today leads with it),
/// so the catalogue keeps a single brass element.
private struct PathBanner: View {
    let path: PathCard

    var body: some View {
        NavigationLink(value: CourseRoute.path(slug: path.slug)) {
            CDCard(tone: .raised, padding: CD.Space.s12) {
                HStack(spacing: CD.Space.s12) {
                    StaticBoardView(fen: path.previewFen, orientation: path.color.side)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text("Rated under 1000? Start here")
                            .cdFont(.meta)
                            .foregroundStyle(CD.accentStrong)
                        Text(path.title)
                            .cdFont(.serifCard)
                            .foregroundStyle(CD.ink)
                        Text("\(CDFormat.plural(path.totals.stages, "stage")) · \(CDFormat.plural(path.totals.exercises, "exercise"))")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CD.ink4)
                }
            }
        }
        .buttonStyle(CDPressStyle())
    }
}

struct CourseCardView: View {
    let course: CourseCard

    var body: some View {
        CDCard(padding: CD.Space.s12) {
            HStack(alignment: .top, spacing: CD.Space.s12) {
                StaticBoardView(
                    fen: course.previewFen,
                    orientation: course.color.side,
                    highlight: course.previewHighlight
                )
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text(course.title)
                        .cdFont(.serifCard)
                        .foregroundStyle(CD.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: CD.Space.s6) {
                        SideSwatch(side: course.color.side)
                        Text("\(course.color == .white ? "White" : "Black") · \(course.level)")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if let progress = course.progress, course.enrollment == .active, progress.learned > 0 {
                        VStack(alignment: .leading, spacing: CD.Space.s4) {
                            CDMeter(value: Double(progress.learned) / Double(max(1, course.totals.lines)))
                            Text("\(CDFormat.count(progress.learned)) of \(CDFormat.plural(course.totals.lines, "line")) learned")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                                .cdNumber()
                        }
                    } else {
                        Text("\(CDFormat.plural(course.totals.lines, "line")) · \(CDFormat.plural(course.totals.moves, "move"))")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CD.ink4)
                    .frame(maxHeight: 104)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(course.title). \(course.color == .white ? "White" : "Black"), \(course.level). \(course.totals.lines) lines."
        )
    }
}

extension CourseCard {
    var previewHighlight: (from: Square, to: Square)? {
        guard let move = previewMove, let from = Square(move.from), let to = Square(move.to) else { return nil }
        return (from, to)
    }
}
