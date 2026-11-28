import Foundation

/// A screen of the app that the home can open. One case per destination.
nonisolated enum HomeRoute: Hashable, Sendable {
    /// Today's Daily 5.
    case daily
    /// A game of the player's, to review.
    case game(id: String)
    /// A learning path (Reach 1000 Elo, Learn chess).
    case path(slug: String)
    /// An opening course: its page.
    case course(slug: String)
    /// The lines of an opening course that are due, in the trainer.
    case courseReview(slug: String)
    /// The catalogue of courses (the Learn tab).
    case courses
    /// The positions from the player's mistakes.
    case mistakes
    /// The player's games (the Games tab).
    case games
    /// Puzzles (in the Train tab).
    case puzzles
    /// The moves of one repertoire that are due, in the trainer.
    case repertoire(id: String)
    /// The repertoires (in the Learn tab): no deck was named.
    case repertoires
    /// The bots (the Play tab).
    case play
    /// The drill of one recurring pattern, from Progress.
    case patternDrill(key: String)
    /// The Progress page.
    case progress
}

/// Turns the server's plan into screens of the app. The server decides the
/// steps and their order (`lib/player/today.ts`); the app only drops a step
/// it cannot open, so no step ever leads nowhere.
nonisolated enum HomeRouter {
    /// Where a step's target leads, or nil when the app has no such screen
    /// (a coach's assignment) or does not know the kind (added on the site later).
    static func route(_ target: TodayStep.Target) -> HomeRoute? {
        switch target.kind.value {
        case .daily: .daily
        case .review: target.gameId.map(HomeRoute.game)
        case .path: target.slug.map(HomeRoute.path)
        case .course: target.slug.map(HomeRoute.course) ?? .courses
        case .courses: .courses
        case .mistakes: .mistakes
        case .deck: deck(target.deck)
        case .puzzles: .puzzles
        case .play: .play
        case .coach, nil: nil
        }
    }

    /// "Repeat your opening lines": the review of the deck that is named,
    /// "course:<slug>" or "repertoire:<id>"; with no deck named, the repertoires.
    static func deck(_ deck: String?) -> HomeRoute? {
        guard let deck else { return .repertoires }
        if let slug = suffix(of: deck, after: "course:") { return .courseReview(slug: slug) }
        if let id = suffix(of: deck, after: "repertoire:") { return .repertoire(id: id) }
        return nil
    }

    private static func suffix(of deck: String, after prefix: String) -> String? {
        deck.hasPrefix(prefix) && deck.count > prefix.count ? String(deck.dropFirst(prefix.count)) : nil
    }

    /// The steps the app shows, in the server's order: every step whose
    /// target has a screen. The first one leads (the server marks it
    /// `primary`); when it is dropped, the next one shown leads.
    static func plan(_ steps: [TodayStep]) -> [PlannedStep] {
        let shown = steps.compactMap { step -> PlannedStep? in
            guard let route = route(step.target) else { return nil }
            return PlannedStep(step: step, route: route, leads: false)
        }
        guard !shown.isEmpty else { return [] }
        let lead = shown.firstIndex { $0.step.primary } ?? 0
        return shown.enumerated().map { index, planned in
            PlannedStep(step: planned.step, route: planned.route, leads: index == lead)
        }
    }
}

nonisolated struct PlannedStep: Hashable, Sendable, Identifiable {
    let step: TodayStep
    let route: HomeRoute
    let leads: Bool

    var id: String { step.key }
}
