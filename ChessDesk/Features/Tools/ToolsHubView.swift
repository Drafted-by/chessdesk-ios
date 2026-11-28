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
                    .cdFont(.body)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                        if index > 0 { CDHairline() }
                        NavigationLink(value: AppRoute.tool(tool)) {
                            HStack(spacing: CD.Space.s12) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(CD.accent)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: CD.Space.s2) {
                                    Text(tool.title)
                                        .cdFont(.bodyStrong)
                                        .foregroundStyle(CD.ink)
                                    Text(tool.summary)
                                        .cdFont(.small)
                                        .foregroundStyle(CD.ink3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CD.ink4)
                            }
                            .padding(.horizontal, CD.Space.s16)
                            .padding(.vertical, CD.Space.s12)
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
                .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
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

    var symbol: String {
        switch self {
        case .analysis: "magnifyingglass"
        case .bestMove: "scope"
        case .coordinates: "square.grid.3x3"
        case .elo: "function"
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
