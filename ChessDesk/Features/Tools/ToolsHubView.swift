import SwiftUI

/// The player's tools that run on the phone alone: no account, no network.
struct ToolsHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                Text("Everything here runs on this phone, with Stockfish on the device. No account needed.")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(ToolRoute.allCases.enumerated()), id: \.element) { index, tool in
                        if index > 0 { CDHairline() }
                        NavigationLink(value: tool) {
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

extension View {
    /// The way to the tools from a tab's first screen: a toolbar button,
    /// and the screens it leads to. Temporary: the final place is the pilot's.
    func toolsEntry() -> some View {
        modifier(ToolsEntry())
    }
}

private struct ToolsEntry: ViewModifier {
    @State private var opensHub = false
    @State private var debugTool: ToolRoute?
    @State private var opensBoardSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        opensHub = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                    .accessibilityLabel("Tools")
                }
            }
        #if DEBUG
            // `-CDRoute boardsettings`: You › Board and sound on its own, to look at it whole.
            .navigationDestination(isPresented: $opensBoardSettings) {
                ScrollView { BoardSettingsSection().pageGutter().padding(.vertical, CD.Space.s16) }
                    .cdPage()
            }
        #endif
            .navigationDestination(isPresented: $opensHub) {
                ToolsHubView()
                    .navigationDestination(for: ToolRoute.self) { $0.screen }
                    .navigationDestination(item: $debugTool) { $0.screen }
            }
        #if DEBUG
            // `-CDRoute tools | analysis | bestmove | coordinates | elo`.
            .onAppear {
                guard let first = DebugLaunch.route?.first, !opensHub else { return }
                if first == "boardsettings" {
                    opensBoardSettings = true
                } else if first == "tools" {
                    opensHub = true
                } else if let tool = ToolRoute(rawValue: first) {
                    opensHub = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        debugTool = tool
                    }
                }
            }
        #endif
    }
}

#Preview {
    NavigationStack { ToolsHubView().navigationDestination(for: ToolRoute.self) { $0.screen } }
}
