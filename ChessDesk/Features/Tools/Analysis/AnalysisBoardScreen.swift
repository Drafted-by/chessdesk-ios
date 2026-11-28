import ChessCore
import StockfishEngine
import SwiftUI
import UIKit

/// The analysis board: play both sides from any position, explore side
/// lines, and read Stockfish's live evaluation, all on the phone.
struct AnalysisBoardScreen: View {
    @State private var model: AnalysisBoardModel
    @State private var showsLoader: Bool
    @State private var notice: String?
    @Environment(\.scenePhase) private var scenePhase

    init(
        tree: MoveTree = MoveTree(),
        cursor: MoveTree.NodeID? = nil,
        orientation: Side = .white,
        opensLoader: Bool = false,
        engine: LiveAnalysisModel = LiveAnalysisModel()
    ) {
        _model = State(initialValue: AnalysisBoardModel(tree: tree, cursor: cursor, orientation: orientation, engine: engine))
        _showsLoader = State(initialValue: opensLoader)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = Self.layoutSize(proxy.size)
            Group {
                if size.width > size.height, size.width >= 700 {
                    sideBySide(size)
                } else {
                    stacked(size)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(min(proxy.size.width / size.width, proxy.size.height / size.height), anchor: .top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .navigationTitle("Analysis board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .overlay(alignment: .top) { noticeView }
        .sheet(isPresented: $showsLoader) {
            LoadPositionSheet { loaded in
                model.load(loaded)
                showsLoader = false
            }
        }
        .task { await model.loadOpenings() }
        .onAppear {
            model.onMovePlayed = { BoardSounds.shared.play(capture: $0) }
            model.start()
        }
        .onDisappear { model.stop() }
        #if DEBUG
            // `-CDAnalysisPGN "1. e4 e5 (1... c5) 2. Nf3" -CDAnalysisPly 3`: a tree on the board.
            .task {
                guard let text = UserDefaults.standard.string(forKey: "CDAnalysisPGN"),
                      case let .success(loaded) = AnalysisInput.read(text)
                else { return }
                model.load(loaded)
                for _ in 0..<UserDefaults.standard.integer(forKey: "CDAnalysisPly") { model.forward() }
            }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    // MARK: Layouts

    /// The space the layout is made for. Debug builds can lay the screen out
    /// for another size and shrink it to fit (`-CDCanvas 1180x820`), to look
    /// at the iPad layouts on a phone.
    private static func layoutSize(_ size: CGSize) -> CGSize {
        #if DEBUG
            if let text = UserDefaults.standard.string(forKey: "CDCanvas") {
                let parts = text.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { return CGSize(width: parts[0], height: parts[1]) }
            }
        #endif
        return size
    }

    /// Phones, and iPad in portrait: board on top, the engine and the moves
    /// under it, the controls at the bottom where the thumb is.
    private func stacked(_ size: CGSize) -> some View {
        let gutter: CGFloat = size.width >= 700 ? CD.Space.s32 : CD.Space.s16
        let rows = size.height > 620 ? 3 : 1
        let reserved = CGFloat(24 + 44 + rows * 44 + 120 + 64 + 24)
        let boardSide = max(220, min(size.width - gutter * 2 - 24, size.height - reserved, 640))
        return VStack(spacing: CD.Space.s8) {
            openingRow
            boardWithBar(side: boardSide)
            EngineLinesPanel(model: model, rows: rows)
            MoveListView(model: model)
                .frame(maxHeight: .infinity)
            controls
        }
        .frame(width: boardSide + 24)
        .frame(maxWidth: .infinity)
        .padding(.top, CD.Space.s4)
        .padding(.bottom, CD.Space.s8)
    }

    /// iPad in landscape and other wide windows: board left, the rest right.
    private func sideBySide(_ size: CGSize) -> some View {
        let column: CGFloat = 380
        let boardSide = max(300, min(size.height - 64, size.width - column - 24 - CD.Space.s32 * 3))
        return HStack(alignment: .top, spacing: CD.Space.s32) {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                openingRow
                boardWithBar(side: boardSide)
            }
            .frame(width: boardSide + 24)
            VStack(spacing: CD.Space.s12) {
                EngineLinesPanel(model: model, rows: 3)
                MoveListView(model: model)
                    .frame(maxHeight: .infinity)
                controls
            }
            .frame(width: column, height: boardSide + 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CD.Space.s16)
    }

    private var openingRow: some View {
        HStack(spacing: CD.Space.s6) {
            if let opening = model.opening {
                Text(opening.eco)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink4)
                    .cdNumber()
                Text(opening.name)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(model.tree.start.fen == Position.startFEN ? "Starting position" : "Set-up position")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
            Spacer(minLength: 0)
            Text("\(model.position.turn == .white ? "White" : "Black") to move")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }

    private func boardWithBar(side: CGFloat) -> some View {
        let engine = model.engine
        let showsEngine = engine.isOn && engine.position == model.position
        return HStack(spacing: 6) {
            EvalBar(line: showsEngine ? engine.best : nil, orientation: model.orientation, winner: winner)
                .frame(height: side)
                .opacity(engine.isOn ? 1 : 0.35)
            BoardView(
                position: model.position,
                orientation: model.orientation,
                lastMove: model.lastMove,
                arrows: showsEngine && model.outcomeText == nil ? arrows(engine.lines) : [],
                movableSide: model.position.turn,
                onMove: { model.play($0) }
            )
            .frame(width: side, height: side)
        }
    }

    private var winner: Side? {
        if case let .checkmate(side) = model.position.outcome { return side }
        return nil
    }

    /// The first move of each line: the best in green, the others in blue (the site's "best" and "alt").
    private func arrows(_ lines: [EngineLine]) -> [BoardArrow] {
        lines.prefix(3).enumerated().compactMap { index, line in
            guard let move = line.moves.first else { return nil }
            return BoardArrow(from: move.from, to: move.to, brush: index == 0 ? .move : .alternative)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: CD.Space.s6) {
            step("backward.end.fill", "Go to start", enabled: model.canGoBack) { model.toStart() }
            step("chevron.left", "Previous move", enabled: model.canGoBack) { model.back() }
            step("chevron.right", "Next move", enabled: model.canGoForward) { model.forward() }
            step("forward.end.fill", "Go to end", enabled: model.canGoForward) { model.toEnd() }
            step("arrow.up.arrow.down", "Flip board", enabled: true) { model.flip() }
            menu
        }
    }

    private func step(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.cd(.secondary))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var menu: some View {
        Menu {
            Button("Load a position or a game", systemImage: "square.and.arrow.down") { showsLoader = true }
            Button("Copy FEN", systemImage: "doc.on.doc") { copy(model.fen, "FEN copied") }
            Button("Copy PGN", systemImage: "doc.on.doc") { copy(model.pgn, "PGN copied") }
            ShareLink(item: model.pgn, subject: Text("Analysis"), preview: SharePreview("Analysis PGN")) {
                Label("Share PGN", systemImage: "square.and.arrow.up")
            }
            if model.node.parent != nil {
                Section {
                    if !model.isOnMainLine {
                        Button("Make main line", systemImage: "arrow.up.to.line") { model.makeMainLine(model.cursor) }
                        Button("Promote variation", systemImage: "arrow.up") { model.promote(model.cursor) }
                    }
                    Button("Delete from this move", systemImage: "trash", role: .destructive) { model.delete(model.cursor) }
                }
            }
            Section {
                Button("New board", systemImage: "arrow.counterclockwise") {
                    model.reset()
                    model.orientation = .white
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(CD.ink)
                .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous).strokeBorder(CD.lineStrong, lineWidth: 1))
        }
        .accessibilityLabel("More")
    }

    private func copy(_ text: String, _ message: String) {
        UIPasteboard.general.string = text
        notice = message
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
            Text(notice)
                .cdFont(.small)
                .foregroundStyle(CD.ink)
                .padding(.horizontal, CD.Space.s16)
                .frame(minHeight: 36)
                .background(CD.surface3, in: Capsule())
                .overlay(Capsule().strokeBorder(CD.lineStrong, lineWidth: 1))
                .padding(.top, CD.Space.s8)
                .transition(.opacity)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(CD.Motion.state) { self.notice = nil }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Paste a FEN or a PGN, choose who is to move, and load it on the board.
/// The site's best-move finder and its analysis board's FEN row, together.
struct LoadPositionSheet: View {
    let onLoad: (AnalysisInput.Loaded) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var side: AnalysisInput.SideToMove = .asWritten
    @State private var failure: String?

    /// White: king g6, queen f7. Black: king h8. The site's practice position.
    static let practiceFEN = "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    Text("Paste a FEN to set up a position, or a PGN to bring in a game with its variations.")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $text)
                        .font(CDFont.mono.font)
                        .foregroundStyle(CD.ink)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(CD.Space.s8)
                        .frame(minHeight: 150)
                        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                        .hairline(failure == nil ? CD.lineStrong : CD.loss, radius: CD.Radius.md)
                        .accessibilityLabel("FEN or PGN")
                        .onChange(of: text) { failure = nil }
                    HStack {
                        Button("Paste", systemImage: "doc.on.clipboard") {
                            text = UIPasteboard.general.string ?? ""
                        }
                        .buttonStyle(.cd(.secondary, size: .small))
                        Spacer()
                        if !text.isEmpty {
                            Button("Clear") { text = "" }
                                .buttonStyle(.cd(.ghost, size: .small))
                        }
                    }
                    if AnalysisInput.looksLikeFEN(text) {
                        VStack(alignment: .leading, spacing: CD.Space.s8) {
                            Text("Side to move")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                            CDSegmented(
                                options: [(.asWritten, "As written"), (.white, "White"), (.black, "Black")],
                                selection: $side
                            )
                        }
                    }
                    if let failure {
                        Text(failure)
                            .cdFont(.small)
                            .foregroundStyle(CD.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Load", action: load)
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    CDHairline()
                    VStack(alignment: .leading, spacing: CD.Space.s8) {
                        Text("Mate or stalemate?")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                        Text("White: king g6, queen f7. Black: king h8. White to move. Compare Qg7 and Qe6.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Load this practice position") {
                            text = Self.practiceFEN
                            side = .asWritten
                            load()
                        }
                        .buttonStyle(.cd(.secondary, fullWidth: true))
                    }
                }
                .pageGutter()
                .padding(.vertical, CD.Space.s16)
                .frame(maxWidth: CD.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .background(CD.canvas.ignoresSafeArea())
            .navigationTitle("Load a position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func load() {
        switch AnalysisInput.read(text, sideToMove: side) {
        case let .success(loaded): onLoad(loaded)
        case let .failure(error): failure = error.message
        }
    }
}

extension AnalysisBoardScreen {
    /// A replayed game, on the board at the move on screen.
    init(game line: GameLine, ply: Int, orientation: Side) {
        let (tree, cursor) = AnalysisBoardModel.tree(from: line, ply: ply)
        self.init(tree: tree, cursor: cursor, orientation: orientation)
    }
}

#if DEBUG
    #Preview("iPhone") {
        NavigationStack {
            AnalysisBoardScreen(engine: LiveAnalysisModel(engine: PreviewEngine()))
        }
    }

    #Preview("iPad landscape", traits: .fixedLayout(width: 1180, height: 820)) {
        NavigationStack {
            AnalysisBoardScreen(engine: LiveAnalysisModel(engine: PreviewEngine()))
        }
    }

    /// Lines that never change, for previews.
    nonisolated struct PreviewEngine: LiveAnalysing {
        func analyse(fen: String, lines: Int) -> AsyncThrowingStream<LiveSearchUpdate, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(LiveSearchUpdate(depth: 18, lines: [
                    EngineEvaluation(centipawns: 31, mate: nil, depth: 18, principalVariation: ["e2e4", "e7e5", "g1f3"]),
                    EngineEvaluation(centipawns: 22, mate: nil, depth: 18, principalVariation: ["d2d4", "d7d5"]),
                    EngineEvaluation(centipawns: 15, mate: nil, depth: 18, principalVariation: ["g1f3", "g8f6"]),
                ]))
                continuation.finish()
            }
        }
    }
#endif
