import Charts
import SwiftUI

// The pieces of Progress, shared by Today and the Progress page: the streak
// in numbers, the 12-week calendar, mistakes mastered, the patterns and the
// rating goal (the site's `components/habit/*`).

/// The Daily 5 streak in numbers (`streak-card.tsx`). Calm copy: a lapsed
/// streak simply starts again.
struct StreakStats: View {
    let streak: DailyStreak
    var showsNote = true

    /// `MAX_FREEZES` and `FREEZE_EVERY_DAYS` of `lib/habit/streak.ts`.
    static let maxFreezes = 2
    static let freezeEveryDays = 7

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Grid(alignment: .leading, horizontalSpacing: CD.Space.s16, verticalSpacing: CD.Space.s12) {
                GridRow {
                    figure("Current streak", CDFormat.plural(streak.current, "day"))
                    figure("Longest streak", CDFormat.plural(streak.longest, "day"))
                }
                GridRow {
                    figure("Freeze days", "\(streak.freezes) of \(Self.maxFreezes)")
                    figure("Today", streak.doneToday ? "Done" : "Open")
                }
            }
            if showsNote {
                Text("A streak counts the days you finish a Daily 5. \(freezeNote)")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var freezeNote: String {
        if streak.freezes >= Self.maxFreezes {
            return "Both freeze days are banked. Each covers one missed day automatically."
        }
        let next = streak.nextFreezeIn.map { " Next one in \(CDFormat.plural($0, "day"))." } ?? ""
        return "Every \(Self.freezeEveryDays) days in a streak earn a freeze day (up to \(Self.maxFreezes)); it covers one missed day automatically.\(next)"
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s2) {
            Text(label)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
            Text(value)
                .cdFont(.cardTitle)
                .foregroundStyle(CD.ink)
                .cdNumber()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Twelve weeks of days, a column per week, the last cell being today.
/// `levels` maps a day's count to 0…3; the Daily 5 calendar uses 0 or 1.
struct DayCalendar: View {
    let counts: [Int]
    let unit: String
    var level: (Int) -> Int = { min(3, $0) }

    private let rows = 7

    var body: some View {
        let columns = Int((Double(counts.count) / Double(rows)).rounded(.up))
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { row in
                            let index = column * rows + row
                            cell(index < counts.count ? level(counts[index]) : -1)
                        }
                    }
                    .frame(maxWidth: 30)
                }
            }
            HStack {
                Text("12 weeks ago")
                Spacer()
                Text("Today")
            }
            .cdFont(.meta)
            .foregroundStyle(CD.ink4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func cell(_ level: Int) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill(level))
            .aspectRatio(1, contentMode: .fit)
    }

    private func fill(_ level: Int) -> Color {
        switch level {
        case ..<0: .clear
        case 0: CD.surface3
        case 1: CD.accent.opacity(0.45)
        case 2: CD.accent.opacity(0.7)
        default: CD.accent
        }
    }

    private var accessibilitySummary: String {
        let active = counts.filter { $0 > 0 }.count
        return "\(unit) on \(active) of the last \(counts.count) days"
    }
}

/// Mistakes mastered: the number, its monthly change and the 12-week line
/// (`MasteredBlock` of `progress-panel.tsx`).
struct MasteredBlock: View {
    let mastered: HomeProgress.Mastered
    var chartHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text("Mistakes mastered")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                Text(CDFormat.count(mastered.current))
                    .cdFont(.metricMedium)
                    .foregroundStyle(CD.ink)
                    .cdNumber()
                Text("of \(CDFormat.count(mastered.total))")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                if mastered.delta30 != 0 {
                    DeltaText(value: mastered.delta30, suffix: "in 30 days")
                }
            }
            .accessibilityElement(children: .combine)
            Text("\(CDFormat.count(mastered.inProgress)) more on their way. A position counts as mastered after four first-try solves in a row (21+ days apart).")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if mastered.series.count > 1 {
                Chart(Array(mastered.series.enumerated()), id: \.offset) { index, point in
                    AreaMark(x: .value("Week", index), y: .value("Mastered", point.mastered))
                        .foregroundStyle(CD.accent.opacity(0.12))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Week", index), y: .value("Mastered", point.mastered))
                        .foregroundStyle(CD.accent)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...max(4, mastered.series.map(\.mastered).max() ?? 0))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(CD.line)
                        AxisValueLabel().foregroundStyle(CD.ink4).font(.custom("Geist-Regular", size: 11))
                    }
                }
                .frame(height: chartHeight)
                .accessibilityLabel("Mistakes mastered over the last 12 weeks, from \(mastered.series.first?.mastered ?? 0) to \(mastered.series.last?.mastered ?? 0)")
            }
        }
    }
}

/// "+4 in 30 days", in the win colour when it goes up.
struct DeltaText: View {
    let value: Int
    let suffix: String

    var body: some View {
        Text("\(value > 0 ? "+" : "−")\(CDFormat.count(abs(value))) \(suffix)")
            .cdFont(.meta)
            .foregroundStyle(value > 0 ? CD.win : CD.loss)
            .cdNumber()
    }
}

/// Recurring patterns, each one a way into a drill, a game or the games
/// (`pattern-list.tsx`). A pattern whose action the app does not know is left out.
struct PatternRows: View {
    let patterns: [HomeProgress.Pattern]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.pattern.id) { index, entry in
                if index > 0 { CDHairline() }
                HomeRouteLink(route: entry.route) { row(entry.pattern) }
            }
        }
    }

    private func row(_ pattern: HomeProgress.Pattern) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s4) {
            Text(pattern.title)
                .cdFont(.bodyStrong)
                .foregroundStyle(CD.ink)
            Text(pattern.detail)
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: CD.Space.s4) {
                Text(pattern.cta)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
            }
            .cdFont(.small)
            .foregroundStyle(CD.accentStrong)
            .padding(.top, CD.Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var shown: [(pattern: HomeProgress.Pattern, route: HomeRoute)] {
        patterns.compactMap { pattern in Self.route(pattern).map { (pattern, $0) } }
    }

    /// Where a pattern leads in the app: its drill, the game to review, or
    /// the games. Nil for an action this version does not know.
    static func route(_ pattern: HomeProgress.Pattern) -> HomeRoute? {
        switch pattern.action.value {
        case .drill: .patternDrill(key: pattern.key)
        case .review: pattern.gameId.map(HomeRoute.game)
        case .games: .games
        case nil: nil
        }
    }
}

/// The rating goal: the distance and trend once set (`GoalBlock`).
struct GoalSummaryView: View {
    let goal: HomeProgress.Goal

    var body: some View {
        let timeClass = TimeClass.label(goal.timeClass)
        if let summary = goal.summary, goal.set {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Rating goal · \(timeClass) \(CDFormat.count(summary.goal))")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    if summary.reached {
                        Text("Reached")
                            .cdFont(.metricMedium)
                            .foregroundStyle(CD.ink)
                    } else {
                        Text(CDFormat.count(summary.distance))
                            .cdFont(.metricMedium)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        Text("to go")
                            .cdFont(.body)
                            .foregroundStyle(CD.ink3)
                    }
                    if let delta = summary.delta30, delta != 0 {
                        DeltaText(value: delta, suffix: "in 30 days")
                    }
                }
                .accessibilityElement(children: .combine)
                Text("\(timeClass) \(CDFormat.count(summary.current)) now\(summary.paceLine.map { ". \($0)." } ?? ".")")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Rating goal")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                let current = goal.samples.last.map { "\(timeClass) \(CDFormat.count($0.rating)) today. " } ?? ""
                Text("\(current)Set a target and see how far it is and how fast you are closing in.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The rating over six months, with the goal drawn across it.
struct GoalChart: View {
    let goal: HomeProgress.Goal

    var body: some View {
        let timeClass = TimeClass.label(goal.timeClass)
        if goal.samples.count > 1 {
            let ratings = goal.samples.map(\.rating) + [goal.summary?.goal].compactMap { $0 }
            let low = (ratings.min() ?? 0) - 40
            let high = (ratings.max() ?? 0) + 40
            Chart {
                ForEach(goal.samples, id: \.at) { sample in
                    LineMark(x: .value("Date", sample.at), y: .value("Rating", sample.rating))
                        .foregroundStyle(CD.ink2)
                        .interpolationMethod(.monotone)
                }
                if let target = goal.summary?.goal, goal.set {
                    RuleMark(y: .value("Goal", target))
                        .foregroundStyle(CD.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Goal").cdFont(.meta).foregroundStyle(CD.accentStrong)
                        }
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale(identifier: "en_US")))
                        .foregroundStyle(CD.ink4)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(CD.line)
                    AxisValueLabel {
                        if let rating = value.as(Int.self) { Text(CDFormat.count(rating)) }
                    }
                    .foregroundStyle(CD.ink4)
                }
            }
            .frame(height: 180)
            .accessibilityLabel("\(timeClass) rating over 6 months\(goal.summary.map { ", goal \($0.goal)" } ?? "")")
        } else {
            Text("Play a few rated \(timeClass.lowercased()) games to see the line.")
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
        }
    }
}

/// Set, change or clear the rating goal (`goal-form.tsx`: 400 to 3,200, in steps of 50).
struct GoalEditor: View {
    let goal: HomeProgress.Goal
    let save: (RatingGoalRequest) async throws -> Void

    @State private var rating: Int
    @State private var timeClass: String
    @State private var isSaving = false
    @State private var error: String?

    init(goal: HomeProgress.Goal, save: @escaping (RatingGoalRequest) async throws -> Void) {
        self.goal = goal
        self.save = save
        _rating = State(initialValue: goal.summary?.goal ?? goal.suggested)
        _timeClass = State(initialValue: TimeClass(rawValue: goal.timeClass)?.rawValue ?? TimeClass.blitz.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Stepper(value: $rating, in: 400...3200, step: 50) {
                HStack {
                    Text("Goal rating").cdFont(.body).foregroundStyle(CD.ink)
                    Spacer()
                    Text(CDFormat.count(rating)).cdFont(.bodyStrong).foregroundStyle(CD.ink).cdNumber()
                }
            }
            .frame(minHeight: 44)
            CDSegmented(options: TimeClass.allCases.map { (value: $0.rawValue, label: $0.label) }, selection: $timeClass)
                .accessibilityLabel("Time control")
            HStack(spacing: CD.Space.s12) {
                Button(goal.set ? "Update goal" : "Set goal") {
                    submit(RatingGoalRequest(rating: rating, timeClass: timeClass))
                }
                .buttonStyle(.cd(.secondary))
                .disabled(isSaving)
                if goal.set {
                    Button("Clear goal") { submit(RatingGoalRequest(rating: nil, timeClass: nil)) }
                        .buttonStyle(.cd(.ghost))
                        .disabled(isSaving)
                }
                if isSaving { ProgressView().tint(CD.ink3) }
            }
            if let error {
                Text(error)
                    .cdFont(.small)
                    .foregroundStyle(CD.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit(_ request: RatingGoalRequest) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await save(request)
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}
