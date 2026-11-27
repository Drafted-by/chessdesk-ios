import ChessCore
import SwiftUI

/// The catalogue of opening courses. Open to guests: the first line of every
/// course is free.
struct CoursesView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: CourseFilter = .all

    enum CourseFilter: Hashable {
        case all, white, black
    }

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(app.backend), AnyHashable(app.accountRevision)]),
            failureTitle: "Courses did not load",
            load: {
                let courses = try await app.api.courses(token: app.token)
                let paths = try? await app.api.paths(token: app.token)
                return (courses, paths?.first { $0.slug == FeaturedPath.slug })
            },
            content: { loaded in catalogue(loaded.0, path: loaded.1) }
        )
        .navigationTitle("Opening courses")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
    }

    private func catalogue(_ courses: [CourseCard], path: PathCard?) -> some View {
        let shown = courses.filter { course in
            switch filter {
            case .all: true
            case .white: course.color == .white
            case .black: course.color == .black
            }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("Opening courses")
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Complete repertoires, taught move by move. The first line of every course is free.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .frame(maxWidth: CD.readingWidth, alignment: .leading)
                }

                if let path {
                    PathBanner(path: path)
                }

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
