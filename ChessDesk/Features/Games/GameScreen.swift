import ChessCore
import StockfishEngine
import SwiftUI
import UIKit

/// One game: replay it move by move, and have the engine on the phone review
/// it. A reviewed game opens on its summary (the evaluation through the
/// game, each side's accuracy, how many moves of each class), then is walked
/// through on the board, every move under the seal of its class and the
/// better move drawn where one was missed.
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
            content: { game in GameDesk(game: game, onReviewed: onReviewed) }
        )
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
    }
}

private struct GameDesk: View {
    enum Mode { case summary, replay }

    let game: GameDetail
    let onReviewed: () -> Void

    @Environment(AppModel.self) private var app
    @State private var line: GameLine
    @State private var ply: Int
    @State private var review: GameReview?
    @State private var mode: Mode
    @State private var starred: Bool
    @State private var progress: Double?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    init(game: GameDetail, onReviewed: @escaping () -> Void) {
        self.game = game
        self.onReviewed = onReviewed
        let line = GameLine(pgn: game.pgn)
        // A stored review of another move list (an edited PGN) is not shown.
        let review = game.review.flatMap { $0.moves.count == line.moves.count ? $0 : nil }
        _line = State(initialValue: line)
        _ply = State(initialValue: 0)
        _review = State(initialValue: review)
        _mode = State(initialValue: review == nil ? .replay : .summary)
        _starred = State(initialValue: game.starred)
    }

    /// The widest the board and what belongs to it get on an iPad.
    private static let deskWidth: CGFloat = 760

    /// The board is seen from the player's side; their bar is under it.
    private var orientation: Side { game.userColor == "black" ? .black : .white }
    private var position: Position { Position(fen: line.fen(atPly: ply)) ?? .start }
    private var current: GameLine.Played? { ply > 0 ? line.moves[ply - 1] : nil }
    private var reviewed: ReviewedMove? { ply > 0 ? review?.moves[ply - 1] : nil }

    var body: some View {
        Group {
            if mode == .summary, let review {
                GameSummaryView(
                    game: game, line: line, review: review, failure: failure,
                    open: { target in
                        ply = target
                        mode = .replay
                    }
                )
            } else {
                replay
            }
        }
        .navigationTitle(mode == .summary && review != nil ? "" : "\(game.white) \(resultMark) \(game.black)")
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
            // `-CDReview YES` on the sample game: review at once. With
            // `-CDReviewPly <n>` the reviewed game then opens on that move.
            .task {
                guard UserDefaults.standard.bool(forKey: "CDReview"), review == nil else { return }
                startReview()
            }
            .onChange(of: review) { _, new in
                let target = UserDefaults.standard.integer(forKey: "CDReviewPly")
                if new != nil, target > 0 {
                    ply = min(line.moves.count, target)
                    mode = .replay
                }
            }
        #endif
    }

    // MARK: The board and its two players

    /// Nothing scrolls: the moves on top, the board between its two players
    /// in the middle of what is left, what the review says of the move, and
    /// the controls under the thumb.
    private var replay: some View {
        VStack(spacing: 0) {
            MoveStrip(line: line, review: review, ply: $ply)
            Spacer(minLength: CD.Space.s4)
            VStack(spacing: 0) {
                playerBar(orientation.opposite)
                BoardView(
                    position: position,
                    orientation: orientation,
                    lastMove: current?.move,
                    arrows: betterMove.map { [BoardArrow(from: $0.from, to: $0.to, brush: .move)] } ?? [],
                    badge: badge,
                    movableSide: nil
                )
                .aspectRatio(1, contentMode: .fit)
                .layoutPriority(1)
                playerBar(orientation)
            }
            .frame(maxWidth: Self.deskWidth)
            Spacer(minLength: CD.Space.s4)
            feedback
                .pageGutter()
                .frame(maxWidth: Self.deskWidth)
            controls
                .pageGutter()
                .padding(.top, CD.Space.s8)
                .padding(.bottom, CD.Space.s8)
                .frame(maxWidth: Self.deskWidth)
        }
        .frame(maxWidth: .infinity)
        .animation(CD.Motion.state, value: ply)
    }

    private var badge: BoardBadge? {
        guard let reviewed, let current else { return nil }
        return BoardBadge(square: current.move.to, kind: reviewed.classification)
    }

    private func playerBar(_ side: Side) -> some View {
        let name = side == .white ? game.white : game.black
        let rating = side == .white ? game.whiteElo : game.blackElo
        let accuracy = review.map { side == .white ? $0.whiteAccuracy : $0.blackAccuracy }
        return HStack(spacing: CD.Space.s8) {
            SideSwatch(side: side, size: 11)
            Text(name)
                .cdFont(.cardTitle)
                .foregroundStyle(CD.ink)
                .lineLimit(1)
            if let rating {
                Text(CDFormat.count(rating))
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
            }
            CapturedRow(material: MaterialDiff(position: position)[side], capturedSide: side.opposite)
            Spacer(minLength: CD.Space.s4)
            if let accuracy {
                Text(GameSummaryView.accuracyText(accuracy))
                    .cdFont(.san)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .accessibilityLabel("Accuracy \(GameSummaryView.accuracyText(accuracy))")
            }
        }
        .padding(.horizontal, CD.Space.s16)
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }

    private var resultMark: String {
        switch game.result {
        case "1-0": "1–0"
        case "0-1": "0–1"
        case "1/2-1/2": "½–½"
        default: "vs"
        }
    }

    private func moveNumber(_ move: GameLine.Played) -> String {
        "\((move.ply + 1) / 2)\(move.side == .white ? "." : "…")"
    }

    /// The engine's move, drawn when the move played lost something.
    private var betterMove: Move? {
        guard let reviewed, reviewed.classification.isError || reviewed.classification == .inaccuracy,
              !reviewed.bestSan.isEmpty, reviewed.bestSan != reviewed.san,
              let before = Position(fen: line.fen(atPly: ply - 1))
        else { return nil }
        return before.move(san: reviewed.bestSan)
    }

    // MARK: What the review says of the move

    /// One line of fixed height, so the board never moves under the finger.
    private var feedback: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            if let progress {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    ProgressView(value: progress).tint(CD.accent)
                    Text("The engine is reading move \(Int(progress * Double(line.fens.count))) of \(line.fens.count). Keep this screen open.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
            } else if let reviewed, let current {
                MoveSeal(reviewed.classification, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(moveNumber(current)) \(current.san) · \(reviewed.classification.label)")
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                        .lineLimit(1)
                    if betterMove != nil {
                        Text("\(reviewed.bestSan) was better.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: CD.Space.s4)
                Text(reviewed.evaluationText)
                    .cdFont(.san)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .accessibilityLabel("Evaluation \(reviewed.evaluationText)")
            } else {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text(current.map { "\(moveNumber($0)) \($0.san)" } ?? (game.opening?.isEmpty == false ? game.opening ?? "" : "Start of the game"))
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                        .lineLimit(1)
                    Text(failure ?? (review == nil
                        ? "The engine on this phone reads every move. About \(estimate)."
                        : subtitle))
                        .cdFont(.small)
                        .foregroundStyle(failure == nil ? CD.ink3 : CD.loss)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, CD.Space.s16)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
        .cardSurface()
        .hairline()
    }

    private var subtitle: String {
        let day = game.playedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_US")))
        return [game.timeClass == "UNKNOWN" ? nil : game.timeClass.capitalized, day]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    // MARK: Controls

    /// The next move of either side the review points at, after this one.
    private var nextKeyMoment: Int? {
        guard let review else { return nil }
        return review.moves.indices.first { $0 + 1 > ply && review.moves[$0].classification.isKeyMoment }.map { $0 + 1 }
    }

    private var controls: some View {
        HStack(spacing: CD.Space.s8) {
            if review != nil {
                Button { mode = .summary } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22)
                }
                .buttonStyle(.cd(.secondary, size: .large))
                .accessibilityLabel("Summary of the review")
                Button("Next key move") {
                    if let nextKeyMoment { ply = nextKeyMoment }
                }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .disabled(nextKeyMoment == nil)
            } else if progress != nil {
                Button("Stop") { task?.cancel() }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
            } else {
                Button("Review", action: startReview)
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .disabled(line.moves.isEmpty)
            }
            step("chevron.left", "Previous move", to: ply - 1)
            step("chevron.right", "Next move", to: ply + 1)
        }
    }

    private func step(_ symbol: String, _ label: String, to target: Int) -> some View {
        let clamped = max(0, min(line.moves.count, target))
        return Button {
            ply = clamped
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 22)
        }
        .buttonStyle(.cd(.secondary, size: .large))
        .disabled(clamped == ply)
        .accessibilityLabel(label)
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
                // The review opens on its summary, as a reviewed game does.
                mode = .summary
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

// MARK: Summary

/// What a review found, before the board: the evaluation through the game,
/// each side's accuracy, and how many moves of each class each side played.
/// The player's column comes first.
struct GameSummaryView: View {
    let game: GameDetail
    let line: GameLine
    let review: GameReview
    var failure: String?
    /// Opens the board on a move (0 is the start).
    let open: (Int) -> Void

    /// The classes of the table, best to worst. Book moves are listed only
    /// when the game has some.
    static let classes: [MoveClass] = [.brilliant, .great, .best, .good, .book, .inaccuracy, .mistake, .blunder]

    static func accuracyText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }

    /// How many moves of a class a side played ("w" or "b").
    static func count(_ kind: MoveClass, side: String, in review: GameReview) -> Int {
        review.moves.count { $0.color == side && $0.classification == kind }
    }

    private var first: Side { game.userColor == "black" ? .black : .white }
    private var sides: [Side] { [first, first.opposite] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text("Game review")
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                EvaluationGraph(review: review, select: open)
                table
                if let failure {
                    Text(failure)
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Walk through the game") { open(min(1, line.moves.count)) }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .frame(maxWidth: 640)
                .pageGutter()
                .padding(.vertical, CD.Space.s8)
                .frame(maxWidth: .infinity)
                .background(CD.canvas)
        }
    }

    private var subtitle: String {
        let day = game.playedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_US")))
        let score: String? = switch game.result {
        case "1-0": "1–0"
        case "0-1": "0–1"
        case "1/2-1/2": "½–½"
        default: nil
        }
        return [score, game.opening, day].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private func name(_ side: Side) -> String { side == .white ? game.white : game.black }
    private func rating(_ side: Side) -> Int? { side == .white ? game.whiteElo : game.blackElo }
    private func accuracy(_ side: Side) -> Double { side == .white ? review.whiteAccuracy : review.blackAccuracy }
    private func letter(_ side: Side) -> String { side == .white ? "w" : "b" }

    private static let valueWidth: CGFloat = 92

    private var table: some View {
        VStack(spacing: 0) {
            // The two players.
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                ForEach(sides, id: \.self) { side in
                    VStack(spacing: CD.Space.s2) {
                        HStack(spacing: CD.Space.s6) {
                            SideSwatch(side: side)
                            Text(name(side))
                                .cdFont(.cardTitle)
                                .foregroundStyle(CD.ink)
                                .lineLimit(1)
                        }
                        if let rating = rating(side) {
                            Text(CDFormat.count(rating))
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                                .cdNumber()
                        }
                    }
                    .frame(width: Self.valueWidth + 14)
                }
            }
            .padding(.vertical, CD.Space.s12)

            CDHairline()

            HStack(spacing: 0) {
                Text("Accuracy")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink2)
                Spacer(minLength: 0)
                ForEach(sides, id: \.self) { side in
                    Text(Self.accuracyText(accuracy(side)))
                        .cdFont(.metricMedium)
                        .foregroundStyle(side == first ? CD.ink : CD.ink2)
                        .cdNumber()
                        .frame(width: Self.valueWidth + 14)
                }
            }
            .padding(.vertical, CD.Space.s12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Accuracy: \(name(sides[0])) \(Self.accuracyText(accuracy(sides[0]))), \(name(sides[1])) \(Self.accuracyText(accuracy(sides[1])))"
            )

            CDHairline()

            VStack(spacing: 0) {
                ForEach(shownClasses, id: \.self) { kind in
                    row(kind)
                }
            }
            .padding(.vertical, CD.Space.s6)
        }
        .padding(.horizontal, CD.Space.s16)
        .cardSurface()
        .hairline()
    }

    private var shownClasses: [MoveClass] {
        Self.classes.filter { kind in
            kind != .book || review.moves.contains { $0.classification == .book }
        }
    }

    /// Label, the player's count, the seal between the two columns, the opponent's count.
    private func row(_ kind: MoveClass) -> some View {
        let counts = sides.map { Self.count(kind, side: letter($0), in: review) }
        return HStack(spacing: 0) {
            Text(kind.label)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
            Spacer(minLength: 0)
            count(counts[0], kind)
            MoveSeal(kind, size: 24)
                .frame(width: 28)
            count(counts[1], kind)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.label): \(name(sides[0])) \(counts[0]), \(name(sides[1])) \(counts[1])")
    }

    private func count(_ value: Int, _ kind: MoveClass) -> some View {
        Text(CDFormat.count(value))
            .cdFont(.sectionTitle)
            .foregroundStyle(value == 0 ? CD.ink4 : kind.color)
            .cdNumber()
            .frame(width: Self.valueWidth)
    }
}

/// The evaluation through the game, as White's share of the outcome: the
/// paper area is White's, what is above it Black's, the hairline in the
/// middle an equal game. A dot marks each move the review points at, in the
/// colour of its class. Tapping the graph opens the board on that move.
private struct EvaluationGraph: View {
    let review: GameReview
    let select: (Int) -> Void

    /// White's share after each position, the start included.
    static func shares(_ review: GameReview) -> [Double] {
        [ReviewMath.winPercent(centipawns: ReviewMath.initialCentipawns)]
            + review.moves.map { ReviewMath.winPercent(centipawns: $0.evalCp, mate: $0.mate) }
    }

    var body: some View {
        let shares = Self.shares(review)
        VStack(spacing: CD.Space.s4) {
            GeometryReader { proxy in
                Canvas { context, size in
                    guard shares.count > 1 else { return }
                    let step = size.width / CGFloat(shares.count - 1)
                    func point(_ index: Int) -> CGPoint {
                        CGPoint(x: CGFloat(index) * step, y: size.height * (1 - shares[index] / 100))
                    }
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: size.height))
                    for index in shares.indices { area.addLine(to: point(index)) }
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(CD.ink.opacity(0.92)))
                    var middle = Path()
                    middle.move(to: CGPoint(x: 0, y: size.height / 2))
                    middle.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(middle, with: .color(CD.ink4), lineWidth: 1)
                    for (index, move) in review.moves.enumerated()
                        where move.classification.isKeyMoment || move.classification == .inaccuracy {
                        let centre = point(index + 1)
                        let radius: CGFloat = move.classification.isKeyMoment ? 4 : 3
                        let ring = CGRect(x: centre.x - radius - 1.5, y: centre.y - radius - 1.5, width: 2 * radius + 3, height: 2 * radius + 3)
                        context.fill(Path(ellipseIn: ring), with: .color(CD.surface3))
                        context.fill(Path(ellipseIn: ring.insetBy(dx: 1.5, dy: 1.5)), with: .color(move.classification.color))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { tap in
                        guard shares.count > 1, proxy.size.width > 0 else { return }
                        let index = Int((tap.location.x / proxy.size.width * CGFloat(shares.count - 1)).rounded())
                        select(max(0, min(shares.count - 1, index)))
                    }
                )
            }
            .frame(height: 112)
            .background(CD.surface3)
            .clipShape(RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
            .hairline(CD.lineStrong, radius: CD.Radius.md)

            // The scale: whose area is whose, and how long the game was.
            HStack(spacing: CD.Space.s6) {
                SideSwatch(side: .white)
                Text("White's share of the game")
                Spacer(minLength: CD.Space.s8)
                Text("\(CDFormat.plural((review.moves.count + 1) / 2, "move")) · tap to open one")
            }
            .cdFont(.meta)
            .foregroundStyle(CD.ink3)
            .cdNumber()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(shares))
    }

    private func summary(_ shares: [Double]) -> String {
        let last = Int((shares.last ?? 50).rounded())
        return "Evaluation through the game, as White's share. It ends at \(last) percent after \(CDFormat.plural((review.moves.count + 1) / 2, "move"))."
    }
}

/// The moves in a row that follows the game; each carries the colour of its
/// class once the game is reviewed.
private struct MoveStrip: View {
    let line: GameLine
    let review: GameReview?
    @Binding var ply: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CD.Space.s2) {
                    ForEach(Array(line.moves.enumerated()), id: \.offset) { offset, move in
                        let index = offset + 1
                        let selected = index == ply
                        Button {
                            ply = index
                        } label: {
                            HStack(spacing: CD.Space.s4) {
                                if move.side == .white || offset == 0 {
                                    Text("\((move.ply + 1) / 2)\(move.side == .white ? "." : "…")")
                                        .foregroundStyle(CD.ink4)
                                }
                                Text(move.san)
                                    .foregroundStyle(color(index) ?? (selected ? CD.ink : CD.ink2))
                            }
                            .cdFont(.san)
                            .cdNumber()
                            .padding(.horizontal, CD.Space.s8)
                            .frame(minHeight: 32)
                            .background(selected ? CD.surface3 : .clear, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
                        }
                        .buttonStyle(CDPressStyle())
                        .id(index)
                    }
                }
                .padding(.horizontal, CD.Space.s12)
            }
            .frame(height: 44)
            .overlay(alignment: .bottom) { CDHairline() }
            .onChange(of: ply) { _, new in
                withAnimation(CD.Motion.state) { proxy.scrollTo(max(1, new), anchor: .center) }
            }
            .onAppear { proxy.scrollTo(max(1, ply), anchor: .center) }
        }
    }

    /// Only the moves worth noticing are coloured; the rest stay ink.
    private func color(_ index: Int) -> Color? {
        guard let move = review?.moves[index - 1], move.classification.coloursItsMove else { return nil }
        return move.classification.color
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
            GameDesk(game: Self.game, onReviewed: {})
                .navigationBarTitleDisplayMode(.inline)
                .cdPage()
        }
    }
#endif
