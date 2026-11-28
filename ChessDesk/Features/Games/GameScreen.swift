import ChessCore
import StockfishEngine
import SwiftUI
import UIKit

/// One game: replay it move by move, and have the engine on the phone review
/// it. A reviewed game shows each side's accuracy, names every move, and
/// points at the better move where one was missed.
struct GameScreen: View {
    let id: String
    var onReviewed: () -> Void = {}

    @Environment(AppModel.self) private var app

    var body: some View {
        Loadable(
            id: AnyHashable(id),
            failureTitle: "This game did not load",
            load: {
                guard let token = app.token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
                return try await app.api.game(id: id, token: token)
            },
            content: { game in GameReplay(game: game, onReviewed: onReviewed) }
        )
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
    }
}

private struct GameReplay: View {
    let game: GameDetail
    let onReviewed: () -> Void

    @Environment(AppModel.self) private var app
    @State private var line: GameLine
    @State private var ply: Int
    @State private var review: GameReview?
    @State private var starred: Bool
    @State private var progress: Double?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    init(game: GameDetail, onReviewed: @escaping () -> Void) {
        self.game = game
        self.onReviewed = onReviewed
        let line = GameLine(pgn: game.pgn)
        _line = State(initialValue: line)
        _ply = State(initialValue: 0)
        // A stored review of another move list (an edited PGN) is not shown.
        _review = State(initialValue: game.review.flatMap { $0.moves.count == line.moves.count ? $0 : nil })
        _starred = State(initialValue: game.starred)
    }

    private var orientation: Side { game.userColor == "black" ? .black : .white }
    private var position: Position { Position(fen: line.fen(atPly: ply)) ?? .start }
    private var current: GameLine.Played? { ply > 0 ? line.moves[ply - 1] : nil }
    private var reviewed: ReviewedMove? { ply > 0 ? review?.moves[ply - 1] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                header
                BoardView(
                    position: position,
                    orientation: orientation,
                    lastMove: current?.move,
                    arrows: betterMove.map { [BoardArrow(from: $0.from, to: $0.to, brush: .move)] } ?? [],
                    movableSide: nil
                )
                .frame(maxWidth: 560)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                controls
                feedback
                MoveStrip(line: line, review: review, ply: $ply)
                if let review {
                    AccuracyRow(game: game, review: review)
                } else {
                    reviewCard
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AnalysisBoardScreen(game: line, ply: ply, orientation: orientation)
                } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(CD.ink2)
                }
                .accessibilityLabel("Analyse from this move")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleStar) {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? CD.accent : CD.ink2)
                }
                .accessibilityLabel(starred ? "Remove the star" : "Star this game")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { task?.cancel() }
        #if DEBUG
            // `-CDReview YES` on the sample game: review at once, then show a move.
            .task {
                guard UserDefaults.standard.bool(forKey: "CDReview"), review == nil else { return }
                startReview()
            }
            .onChange(of: review) { _, new in
                if new != nil, UserDefaults.standard.bool(forKey: "CDReview") { ply = min(line.moves.count, 18) }
            }
        #endif
    }

    // MARK: Pieces of the screen

    private var header: some View {
        VStack(alignment: .leading, spacing: CD.Space.s4) {
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                Text("\(game.white) \(resultMark) \(game.black)")
                    .cdFont(.serifCard)
                    .foregroundStyle(CD.ink)
                    .lineLimit(2)
            }
            Text(subtitle)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
                .lineLimit(2)
        }
    }

    private var resultMark: String {
        switch game.result {
        case "1-0": "1–0"
        case "0-1": "0–1"
        case "1/2-1/2": "½–½"
        default: "vs"
        }
    }

    private var subtitle: String {
        let day = game.playedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_US")))
        let ratings = [game.whiteElo, game.blackElo].compactMap { $0 }.map(String.init).joined(separator: " and ")
        return [game.opening, ratings.isEmpty ? nil : "rated \(ratings)", day]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private var controls: some View {
        HStack(spacing: CD.Space.s8) {
            step("backward.end.fill", "First move", to: 0)
            step("chevron.left", "Previous move", to: ply - 1)
            Text(ply == 0 ? "Start" : "\(moveNumber(current)) \(current?.san ?? "")")
                .cdFont(.san)
                .foregroundStyle(CD.ink)
                .frame(maxWidth: .infinity)
                .cdNumber()
            step("chevron.right", "Next move", to: ply + 1)
            step("forward.end.fill", "Last move", to: line.moves.count)
        }
    }

    private func step(_ symbol: String, _ label: String, to target: Int) -> some View {
        let clamped = max(0, min(line.moves.count, target))
        return Button {
            ply = clamped
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22, height: 44)
        }
        .buttonStyle(.cd(.secondary))
        .disabled(clamped == ply)
        .accessibilityLabel(label)
    }

    private func moveNumber(_ move: GameLine.Played?) -> String {
        guard let move else { return "" }
        return "\((move.ply + 1) / 2)\(move.side == .white ? "." : "...")"
    }

    /// The engine's move, drawn when the move played lost something.
    private var betterMove: Move? {
        guard let reviewed, reviewed.classification.isError || reviewed.classification == .inaccuracy,
              !reviewed.bestSan.isEmpty, reviewed.bestSan != reviewed.san,
              let before = Position(fen: line.fen(atPly: ply - 1))
        else { return nil }
        return before.move(san: reviewed.bestSan)
    }

    @ViewBuilder private var feedback: some View {
        if let reviewed {
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s12) {
                Circle().fill(reviewed.classification.color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text(reviewed.classification.label)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                    if betterMove != nil {
                        Text("\(reviewed.bestSan) was better.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                    }
                }
                Spacer()
                Text(reviewed.evaluationText)
                    .cdFont(.san)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .accessibilityLabel("Evaluation \(reviewed.evaluationText)")
            }
            .padding(.horizontal, CD.Space.s16)
            .frame(minHeight: 56)
            .cardSurface()
            .hairline()
        }
    }

    private var reviewCard: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Review this game")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                if let progress {
                    ProgressView(value: progress)
                        .tint(CD.accent)
                    Text("The engine is reading move \(Int(progress * Double(line.fens.count))) of \(line.fens.count). Keep this screen open.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                    Button("Stop") { task?.cancel() }
                        .buttonStyle(.cd(.secondary, fullWidth: true))
                } else {
                    Text("Stockfish, on this phone, reads every move: your accuracy, the moves that cost you, and what was better. About \(estimate).")
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure {
                        Text(failure)
                            .cdFont(.small)
                            .foregroundStyle(CD.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Review", action: startReview)
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .disabled(line.moves.isEmpty)
                }
            }
        }
    }

    /// At most a second and a half per position.
    private var estimate: String {
        let seconds = Double(line.fens.count) * 1.5
        return seconds < 90 ? "a minute" : "\(Int((seconds / 60).rounded())) minutes"
    }

    // MARK: Actions

    private func startReview() {
        guard progress == nil else { return }
        failure = nil
        progress = 0
        let line = line
        let total = Double(line.fens.count)
        task = Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                progress = nil
            }
            do {
                // A review may use the phone's fast cores; the trainer goes back to one.
                if let network = DeviceEngine.networkURL { try? await StockfishEngine.shared.start(network: network) }
                await StockfishEngine.shared.configure(threads: 3, hashMegabytes: 64)
                let done = try await GameReviewer().review(line) { count in
                    await MainActor.run { progress = Double(count) / total }
                }
                await StockfishEngine.shared.configure(threads: 1, hashMegabytes: 16)
                review = done
                await save(done)
            } catch is CancellationError {
                await StockfishEngine.shared.configure(threads: 1, hashMegabytes: 16)
            } catch {
                await StockfishEngine.shared.configure(threads: 1, hashMegabytes: 16)
                failure = "The engine could not review this game. Try again."
            }
        }
    }

    private func save(_ review: GameReview) async {
        guard let token = app.token else { return }
        do {
            try await app.api.saveReview(game: game.id, review: review, token: token)
            onReviewed()
        } catch let error as APIError {
            failure = "Reviewed, but not saved to your account: \(error.message)"
        } catch {
            failure = "Reviewed, but not saved to your account."
        }
    }

    private func toggleStar() {
        guard let token = app.token else { return }
        starred.toggle()
        let wanted = starred
        Task {
            do {
                try await app.api.setStar(game: game.id, starred: wanted, token: token)
            } catch {
                starred = !wanted
            }
        }
    }
}

/// The moves in a row that scrolls with the game; each carries the colour of
/// its class once the game is reviewed.
private struct MoveStrip: View {
    let line: GameLine
    let review: GameReview?
    @Binding var ply: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CD.Space.s4) {
                    ForEach(line.moves, id: \.ply) { move in
                        let index = move.ply - (line.moves.first?.ply ?? 1) + 1
                        let selected = index == ply
                        Button {
                            ply = index
                        } label: {
                            HStack(spacing: CD.Space.s4) {
                                if move.side == .white {
                                    Text("\((move.ply + 1) / 2).")
                                        .foregroundStyle(CD.ink4)
                                }
                                Text(move.san)
                                    .foregroundStyle(color(index) ?? (selected ? CD.ink : CD.ink2))
                            }
                            .cdFont(.san)
                            .cdNumber()
                            .padding(.horizontal, CD.Space.s8)
                            .frame(minHeight: 36)
                            .background(selected ? CD.surface3 : .clear, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
                        }
                        .buttonStyle(CDPressStyle())
                        .id(index)
                    }
                }
                .padding(.horizontal, CD.Space.s8)
            }
            .frame(minHeight: 44)
            .cardSurface()
            .hairline()
            .onChange(of: ply) { _, new in
                withAnimation(CD.Motion.state) { proxy.scrollTo(max(1, new), anchor: .center) }
            }
        }
    }

    /// Only the moves worth noticing are coloured; the rest stay ink.
    private func color(_ index: Int) -> Color? {
        guard let move = review?.moves[index - 1] else { return nil }
        switch move.classification {
        case .inaccuracy, .mistake, .blunder, .brilliant, .great: return move.classification.color
        default: return nil
        }
    }
}

private struct AccuracyRow: View {
    let game: GameDetail
    let review: GameReview

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "Accuracy")
            HStack(spacing: CD.Space.s12) {
                card(game.white, review.whiteAccuracy, color: "w")
                card(game.black, review.blackAccuracy, color: "b")
            }
        }
    }

    private func card(_ name: String, _ accuracy: Double, color: String) -> some View {
        let errors = review.moves.filter { $0.color == color }
        let blunders = errors.count { $0.classification == .blunder }
        let mistakes = errors.count { $0.classification == .mistake }
        return CDCard {
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                Text(name)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .lineLimit(1)
                Text(accuracy.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US"))))
                    .cdFont(.metricMedium)
                    .foregroundStyle(CD.ink)
                    .cdNumber()
                Text("\(CDFormat.plural(blunders, "blunder")), \(CDFormat.plural(mistakes, "mistake"))")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension MoveClass {
    /// Semantic colours: errors warm, finds brass, the rest quiet.
    var color: Color {
        switch self {
        case .blunder: CD.danger
        case .mistake: CD.loss
        case .inaccuracy: CD.caution
        case .brilliant, .great: CD.accent
        case .best: CD.win
        case .good, .book: CD.ink3
        }
    }
}

extension ReviewedMove {
    /// White's view: "+1.3", "−0.4", "#3" (White mates), "#−2".
    var evaluationText: String {
        if let mate {
            if mate == 0 { return "#" }
            return mate > 0 ? "#\(mate)" : "#−\(-mate)"
        }
        guard let evalCp else { return "" }
        let pawns = evalCp / 100
        let text = abs(pawns).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        return pawns >= 0 ? "+\(text)" : "−\(text)"
    }
}

#if DEBUG
    /// `-CDRoute games/sample`: a game on screen without an account, to check
    /// the layout in the simulator. Its review is run by the real engine.
    struct SampleGameScreen: View {
        static let game = GameDetail(
            id: "sample", source: "LICHESS", white: "ana_plays", black: "benoit64", whiteElo: 1432, blackElo: 1418,
            result: "1-0", timeClass: "RAPID", opening: "Italian Game", userColor: "white",
            playedAt: Date(timeIntervalSince1970: 1_795_000_000), ply: 23, starred: false, reviewed: false,
            pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7. Nc3 Nxe4 8. O-O Nxc3 9. bxc3 Bxc3 10. Qb3 Bxa1 11. Bxf7+ Kf8 12. Bg5 1-0",
            url: nil, review: nil
        )

        var body: some View {
            GameReplay(game: Self.game, onReviewed: {})
                .navigationBarTitleDisplayMode(.inline)
                .cdPage()
        }
    }
#endif
