import Foundation

/// A screen of the app that the home can open. One case per destination;
/// `HomeRouter` decides which ones this build can open.
nonisolated enum HomeRoute: Hashable, Sendable {
    /// Today's Daily 5.
    case daily
    /// A game of the player's, to review.
    case game(id: String)
    /// A learning path (Reach 1000 Elo, Learn chess).
    case path(slug: String)
    /// An opening course, and the reviews due in it.
    case course(slug: String)
    /// The catalogue of courses (the Courses tab).
    case courses
    /// The positions from the player's mistakes.
    case mistakes
    /// Rated puzzles. Built on `feat/puzzles`: the pilot wires it at integration.
    case puzzles
    /// One repertoire's lines due for review. Built on `feat/repertoires`: wired at integration.
    case repertoire(id: String)
    /// The repertoires (the deck with the most due moves was not named). Wired at integration.
    case repertoires
    /// The bots.
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

    /// "course:<slug>" opens the course; "repertoire:<id>" the repertoire;
    /// no deck named, the repertoires.
    static func deck(_ deck: String?) -> HomeRoute? {
        guard let deck else { return .repertoires }
        if deck.hasPrefix("course:") { return .course(slug: String(deck.dropFirst("course:".count))) }
        if deck.hasPrefix("repertoire:") { return .repertoire(id: String(deck.dropFirst("repertoire:".count))) }
        return nil
    }

    /// The destinations this branch has a screen for. The others are built on
    /// other branches; the pilot adds them here when it connects their screens
    /// in `TodayDestinations` (see `HomeDestinations.swift`).
    static func opens(_ route: HomeRoute) -> Bool {
        switch route {
        case .daily, .game, .path, .course, .courses, .mistakes, .play, .patternDrill, .progress: true
        case .puzzles, .repertoire, .repertoires: false
        }
    }

    /// The steps the app shows, in the server's order. The first one leads
    /// (the server marks it `primary`); when it is dropped, the next one shown leads.
    static func plan(_ steps: [TodayStep], opens: (HomeRoute) -> Bool = opens) -> [PlannedStep] {
        let shown = steps.compactMap { step -> PlannedStep? in
            guard let route = route(step.target), opens(route) else { return nil }
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
