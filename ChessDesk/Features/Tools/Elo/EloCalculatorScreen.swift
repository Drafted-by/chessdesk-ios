import SwiftUI

/// The site's Elo calculator (`apps/web/components/elo-calculator.tsx`):
/// what one game does to a FIDE rating, and the performance over several.
struct EloCalculatorScreen: View {
    enum Tab: Hashable { case change, performance }

    @State private var tab: Tab = .change
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                CDSegmented(options: [(.change, "Rating change"), (.performance, "Performance rating")], selection: $tab)
                switch tab {
                case .change: RatingChangeForm(focused: $focused)
                case .performance: PerformanceForm(focused: $focused)
                }
            }
            .pageGutter()
            .padding(.vertical, CD.Space.s16)
            .frame(maxWidth: CD.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Elo calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .cdPage()
    }
}

nonisolated enum GameResultChoice: String, CaseIterable, Hashable {
    case win, draw, loss

    var score: Double {
        switch self {
        case .win: 1
        case .draw: 0.5
        case .loss: 0
        }
    }

    var label: String { rawValue.capitalized }
}

private struct RatingChangeForm: View {
    let focused: FocusState<Bool>.Binding

    @State private var player = "1500"
    @State private var opponent = "1600"
    @State private var result: GameResultChoice = .win
    @State private var k = 20

    private static let kNotes: [Int: String] = [
        40: "New players for their first 30 rated games, and players until the end of the year they turn 18 while rated under 2300.",
        20: "Standard factor for most players once their rating is established and below 2400.",
        10: "Players who have ever reached a published rating of 2400 or higher.",
    ]

    var body: some View {
        let computed = RatingChangeResult(
            player: EloMath.rating(player), opponent: EloMath.rating(opponent), score: result.score, k: Double(k)
        )
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            HStack(spacing: CD.Space.s12) {
                RatingField(title: "Your rating", text: $player, focused: focused)
                RatingField(title: "Opponent rating", text: $opponent, focused: focused)
            }
            field("Result") {
                CDSegmented(options: GameResultChoice.allCases.map { ($0, $0.label) }, selection: $result)
            }
            field("K-factor") {
                CDSegmented(options: [(40, "K = 40"), (20, "K = 20"), (10, "K = 10")], selection: $k)
                Text(Self.kNotes[k] ?? "")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ResultTiles(tiles: [
                ("Expected score", computed?.expected),
                ("Rating change", computed?.delta),
                ("New rating", computed?.newRating),
            ])
            if computed?.capped == true {
                Text("The gap is over 400 points, so it is counted as 400, as FIDE does for players rated below 2650.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text(title).cdFont(.meta).foregroundStyle(CD.ink2)
            content()
        }
    }
}

private struct PerformanceForm: View {
    let focused: FocusState<Bool>.Binding

    struct Row: Identifiable {
        let id = UUID()
        var opponent: String
        var result: GameResultChoice
    }

    @State private var rows: [Row] = [
        Row(opponent: "2000", result: .win),
        Row(opponent: "2100", result: .draw),
        Row(opponent: "1900", result: .loss),
    ]

    var body: some View {
        let games = rows.compactMap { row in EloMath.rating(row.opponent).map { EloMath.Game(opponent: $0, score: row.result.score) } }
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            ForEach($rows) { $row in
                HStack(alignment: .bottom, spacing: CD.Space.s8) {
                    RatingField(title: "Opponent rating", text: $row.opponent, focused: focused)
                        .frame(maxWidth: 140)
                    CDSegmented(options: GameResultChoice.allCases.map { ($0, $0.label) }, selection: $row.result)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CDPressStyle())
                    .foregroundStyle(CD.ink3)
                    .disabled(rows.count <= 1)
                    .opacity(rows.count <= 1 ? 0.4 : 1)
                    .accessibilityLabel("Remove game")
                }
            }
            Button("Add game", systemImage: "plus") { rows.append(Row(opponent: "", result: .win)) }
                .buttonStyle(.cd(.secondary))
            ResultTiles(tiles: summary(games))
        }
    }

    private func summary(_ games: [EloMath.Game]) -> [(String, String?)] {
        guard !games.isEmpty else { return [("Average opponent", nil), ("Score", nil), ("Performance rating", nil)] }
        let average = games.reduce(0) { $0 + $1.opponent } / Double(games.count)
        let percent = games.reduce(0) { $0 + $1.score } / Double(games.count) * 100
        let english = Locale(identifier: "en_US")
        return [
            ("Average opponent", String(Int(average.rounded(.toNearestOrAwayFromZero)))),
            ("Score", percent.formatted(.number.precision(.fractionLength(0...1)).locale(english)) + "%"),
            ("Performance rating", EloMath.performance(games).map(String.init)),
        ]
    }
}

private struct RatingField: View {
    let title: String
    @Binding var text: String
    let focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            Text(title).cdFont(.meta).foregroundStyle(CD.ink2).lineLimit(1)
            TextField("1500", text: $text)
                .keyboardType(.numberPad)
                .focused(focused)
                .cdFont(.bodyStrong)
                .cdNumber()
                .foregroundStyle(CD.ink)
                .padding(.horizontal, CD.Space.s12)
                .frame(minHeight: 44)
                .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                .hairline(CD.lineStrong, radius: CD.Radius.md)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResultTiles: View {
    let tiles: [(String, String?)]

    var body: some View {
        HStack(spacing: CD.Space.s8) {
            ForEach(tiles, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text(value ?? "–")
                        .cdFont(.metricMedium)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(title)
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CD.Space.s12)
                .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
                .hairline()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    NavigationStack { EloCalculatorScreen() }
}
