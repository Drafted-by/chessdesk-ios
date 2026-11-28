import SwiftUI

/// The tools reached from Games besides the analysis board: they run on
/// the phone alone, with no account and no network. (The coordinates trainer
/// is in Train.)
struct ToolsHubView: View {
    private let tools: [ToolRoute] = [.bestMove, .elo]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                Text("Both run on this phone. No account needed.")
                    .cdFont(.ledeSmall)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                        if index > 0 { CDHairline() }
                        NavigationLink(value: AppRoute.tool(tool)) {
                            FeatureRow(emblem: tool.emblem, title: tool.title, detail: tool.summary)
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
                .cardSurface()
                .hairline()
            }
            .pageGutter()
            .padding(.vertical, CD.Space.s16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
    }
}

/// Each tool, as a navigation value.
enum ToolRoute: String, Hashable, CaseIterable {
    case analysis
    case bestMove = "bestmove"
    case coordinates
    case elo

    var title: String {
        switch self {
        case .analysis: "Analysis board"
        case .bestMove: "Best move in a position"
        case .coordinates: "Coordinates"
        case .elo: "Elo calculator"
        }
    }

    var summary: String {
        switch self {
        case .analysis: "Play both sides, explore side lines, and read the engine live."
        case .bestMove: "Paste a FEN or a PGN, and Stockfish shows the best move and its line."
        case .coordinates: "Tap the named square, as many as you can in 30 seconds."
        case .elo: "What a game does to your rating, and your performance in a tournament."
        }
    }

    var emblem: Emblem.Kind {
        switch self {
        case .analysis: .analysis
        case .bestMove: .nextMove
        case .coordinates: .coordinates
        case .elo: .rating
        }
    }

    @ViewBuilder var screen: some View {
        switch self {
        case .analysis: AnalysisBoardScreen()
        case .bestMove: AnalysisBoardScreen(opensLoader: true)
        case .coordinates: CoordinateTrainerScreen()
        case .elo: EloCalculatorScreen()
        }
    }
}

#Preview {
    NavigationStack { ToolsHubView().appDestinations() }
}
