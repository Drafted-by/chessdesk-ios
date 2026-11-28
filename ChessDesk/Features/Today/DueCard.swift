import ChessCore
import SwiftUI

/// What is due for review, deck by deck: the opening courses the player
/// follows and their own repertoires. A row opens the review of its deck in
/// the trainer.
struct DueCard: View {
    let due: DueSummary
    let courses: [CourseCard]

    @Environment(HomeNavigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What it is and how much: the course emblem names the feature.
            HStack(alignment: .center, spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
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
                Spacer(minLength: CD.Space.s8)
                Emblem(kind: .course, size: 48, surface: CD.surface2)
            }
            .padding(.horizontal, CD.Space.s20)
            .padding(.top, CD.Space.s20)
            .padding(.bottom, CD.Space.s16)

            CDHairline()

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { CDHairline().padding(.leading, CD.Space.s20 + 44 + CD.Space.s12) }
                    HomeRouteLink(route: row.route) { label(row) }
                        .accessibilityHint("Opens the review")
                }
            }
        }
        .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
        .hairline(CD.lineStrong)
    }

    /// The position of the course, small, as the row's picture; a repertoire
    /// of the player's own takes its emblem.
    private func label(_ row: DueRow) -> some View {
        let deck = row.deck
        // The server spells it "black" or "BLACK".
        let side: Side = deck.color.lowercased().hasPrefix("b") ? .black : .white
        return HStack(spacing: CD.Space.s12) {
            Group {
                if case let .course(slug) = row.target, let course = courses.first(where: { $0.slug == slug }) {
                    StaticBoardView(fen: course.previewFen, orientation: course.color.side, highlight: course.previewHighlight)
                } else {
                    Emblem(kind: .repertoire, size: 40, surface: CD.surface2)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                Text(deck.name)
                    .cdFont(.serifCard)
                    .foregroundStyle(CD.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: CD.Space.s6) {
                    SideSwatch(side: side)
                    Text("\(side == .white ? "White" : "Black") · \(CDFormat.plural(deck.progress.dueMoves, "move"))")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
            }
            Spacer(minLength: CD.Space.s8)
            Text(CDFormat.plural(deck.progress.dueLines, "line"))
                .cdFont(.small)
                .foregroundStyle(CD.accentStrong)
                .cdNumber()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .padding(.horizontal, CD.Space.s20)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var rows: [DueRow] { DueRow.rows(due: due, courses: courses) }
}

/// A deck with something due, and what its row opens: the review of a
/// course, or the review of one of the player's own repertoires.
struct DueRow {
    enum Target: Hashable {
        case course(slug: String)
        case repertoire(RepertoireTrainingRequest)
    }

    let deck: DueSummary.Deck
    let target: Target

    /// The trainer the row opens.
    var route: HomeRoute {
        switch target {
        case let .course(slug): .courseReview(slug: slug)
        case let .repertoire(request): .repertoire(id: request.id)
        }
    }

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
