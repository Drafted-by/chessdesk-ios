import SwiftUI

/// Progress (the site's `/progress`): the Daily 5 streak and its 12-week
/// calendar, mistakes mastered, the patterns of the player's games with their
/// drills, and the rating goal. The streak is the screen's plate.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var navigator
    @State private var localRevision = 0

    var body: some View {
        Loadable(
            id: AnyHashable([navigator.revision, localRevision, app.accountRevision]),
            failureTitle: "Progress did not load",
            load: {
                guard let token = app.token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
                return try await app.api.progress(token: token)
            },
            content: { page in content(page) }
        )
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
    }

    private func content(_ page: ProgressPage) -> some View {
        let progress = page.progress
        let empty = progress.mastered.total == 0 && progress.patterns.isEmpty && progress.goal == nil
        return ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("What changes as you train: positions you no longer miss, the patterns in your games, and the distance to your rating goal.")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                streak(page)

                if empty {
                    CDCard(padding: CD.Space.s20) {
                        VStack(alignment: .leading, spacing: CD.Space.s8) {
                            Text("Your progress starts with one reviewed game")
                                .cdFont(.cardTitle)
                                .foregroundStyle(CD.ink)
                            Text("Every mistake from a reviewed game becomes a position to master; a few games reveal your patterns. Review one in Games.")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    section("Mistakes mastered") {
                        CDCard(padding: CD.Space.s20) {
                            VStack(alignment: .leading, spacing: CD.Space.s16) {
                                MasteredBlock(mastered: progress.mastered, chartHeight: 180)
                                if progress.mastered.total > 0 {
                                    Button("Open the drill") { navigator.open(.mistakes) }
                                        .buttonStyle(.cd(.secondary))
                                }
                            }
                        }
                    }
                    section("Patterns in your games", detail: "From your last 90 days of games and your 60 most recent reviews.") {
                        CDCard(padding: CD.Space.s16) {
                            if progress.patterns.isEmpty {
                                Text("No clear pattern yet. A few more reviewed games will show where yours turn.")
                                    .cdFont(.small)
                                    .foregroundStyle(CD.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                PatternRows(patterns: progress.patterns)
                            }
                        }
                    }
                }

                if let goal = progress.goal {
                    section("Rating goal", detail: "\(TimeClass.label(goal.timeClass)), rated games of the last 6 months.") {
                        CDCard(padding: CD.Space.s20) {
                            VStack(alignment: .leading, spacing: CD.Space.s20) {
                                GoalSummaryView(goal: goal)
                                GoalChart(goal: goal)
                                CDHairline()
                                GoalEditor(goal: goal, save: saveGoal)
                                    .id(goal)
                            }
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { localRevision += 1 }
        .debugScrollAnchor()
    }

    private func streak(_ page: ProgressPage) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                Text("Daily 5 streak")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(page.line)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            }
            StreakStats(streak: page.streak)
            DayCalendar(counts: page.calendar, unit: "Daily 5 finished") { $0 > 0 ? 3 : 0 }
            Button(page.streak.doneToday ? "Five more" : "Start Daily 5") { navigator.open(.daily) }
                .buttonStyle(.cd(page.streak.doneToday ? .secondary : .primary, fullWidth: true))
        }
        .plate(padding: CD.Space.s20)
    }

    private func section(_ title: String, detail: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: title, detail: detail)
            content()
        }
    }

    private func saveGoal(_ request: RatingGoalRequest) async throws {
        guard let token = app.token else { return }
        _ = try await app.api.setRatingGoal(request, token: token)
        localRevision += 1
    }
}
