import SwiftUI

/// What is due for review, deck by deck: the opening courses the player
/// follows and their own repertoires. A row opens the review of its deck in
/// the trainer.
struct DueCard: View {
    let due: DueSummary
    let courses: [CourseCard]

    @Environment(HomeNavigator.self) private var navigator

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
                        HomeRouteLink(route: row.route) { label(row.deck) }
                            .accessibilityHint("Opens the review")
                    }
                }
            }
        }
    }

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
