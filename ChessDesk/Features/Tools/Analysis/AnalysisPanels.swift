import ChessCore
import SwiftUI

/// The evaluation bar beside the board (`components/review/eval-bar.tsx`):
/// White's share fills from White's side of the board, the score is printed
/// at the end of the side that leads.
struct EvalBar: View {
    let line: EngineLine?
    let orientation: Side
    /// A checkmate on the board: the bar is the winner's, whatever the engine says.
    var winner: Side?

    var body: some View {
        let share = winner.map { $0 == .white ? 1 : 0 }
            ?? EngineScore.whiteShare(whiteCentipawns: line?.whiteCentipawns, whiteMate: line?.whiteMate) / 100
        let whiteLeads = winner.map { $0 == .white } ?? line.map { ($0.whiteMate ?? $0.whiteCentipawns ?? 0) >= 0 } ?? true
        let whiteAtBottom = orientation == .white
        let labelAtBottom = whiteLeads == whiteAtBottom
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: whiteAtBottom ? .bottom : .top) {
                CD.sideBlack
                CD.sideWhite
                    .frame(height: height * share)
                Rectangle()
                    .fill(CD.Board.dark.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity)
                Text(label)
                    .font(.custom("Geist-SemiBold", fixedSize: 9))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(whiteLeads ? CD.sideBlack : CD.sideWhite)
                    .padding(.vertical, 4)
                    .frame(maxHeight: .infinity, alignment: labelAtBottom ? .bottom : .top)
            }
            .animation(CD.Motion.state, value: share)
        }
        .frame(width: 18)
        .clipShape(RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous).strokeBorder(CD.line, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(winner.map { "\($0 == .white ? "White" : "Black") has mated" } ?? "Evaluation \(line?.displayScore ?? "even")")
    }

    /// The score without its sign: its place says who leads. "0.0" when even.
    private var label: String {
        if winner != nil { return "#" }
        guard let line else { return "0.0" }
        if let mate = line.whiteMate { return "#\(abs(mate))" }
        let pawns = Double(abs(line.whiteCentipawns ?? 0)) / 100
        return pawns >= 10
            ? pawns.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
            : pawns.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }
}

/// Stockfish's best lines for the position on screen. Tap a line to play
/// its first move; hold it to play the whole line.
struct EngineLinesPanel: View {
    let model: AnalysisBoardModel
    var rows = 3

    var body: some View {
        let engine = model.engine
        VStack(spacing: 0) {
            HStack(spacing: CD.Space.s8) {
                Text("Stockfish")
                    .cdFont(.cardTitle)
                    .foregroundStyle(CD.ink)
                if engine.isOn, engine.depth > 0 {
                    Text("Depth \(engine.depth)")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
                Spacer()
                Toggle("Engine", isOn: Binding(get: { engine.isOn }, set: { engine.isOn = $0 }))
                    .labelsHidden()
                    .tint(CD.accent)
                    .accessibilityLabel("Engine")
            }
            .padding(.horizontal, CD.Space.s12)
            .frame(minHeight: 44)
            CDHairline()
            content(engine)
                .frame(minHeight: CGFloat(rows) * 44, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
        .hairline()
    }

    @ViewBuilder private func content(_ engine: LiveAnalysisModel) -> some View {
        if let outcome = model.outcomeText {
            message(outcome, color: CD.ink)
        } else if !engine.isOn {
            message("Engine off. Turn it on for live lines.")
        } else if case let .unavailable(text) = engine.status {
            message(text, color: CD.loss)
        } else if let problem = model.position.setupProblem {
            message(problem.message, color: CD.loss)
        } else if engine.lines.isEmpty || engine.position != model.position {
            message("Evaluating…")
        } else {
            VStack(spacing: 0) {
                ForEach(engine.lines.prefix(rows)) { line in
                    if line.id > 1 { CDHairline() }
                    row(line)
                }
            }
        }
    }

    private func message(_ text: String, color: Color = CD.ink3) -> some View {
        Text(text)
            .cdFont(.small)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CD.Space.s12)
            .padding(.vertical, CD.Space.s12)
    }

    private func row(_ line: EngineLine) -> some View {
        Button {
            model.play(line, count: 1)
        } label: {
            HStack(spacing: CD.Space.s8) {
                ScoreChip(line: line)
                movesText(line)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, CD.Space.s12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .contextMenu {
            Button("Play this line") { model.play(line) }
            Button("Play the first move") { model.play(line, count: 1) }
        }
        .accessibilityLabel("\(line.displayScore), \(line.san.prefix(6).joined(separator: " "))")
        .accessibilityHint("Plays the first move. Hold to play the whole line.")
    }

    /// "12. Nf3 Nc6 13. Bb5": the first move stands out.
    private func movesText(_ line: EngineLine) -> Text {
        var text = Text("")
        var ply = model.node.ply + 1
        for (index, san) in line.san.enumerated() {
            var number = ""
            if ply % 2 == 1 {
                number = "\((ply + 1) / 2). "
            } else if index == 0 {
                number = "\(ply / 2)… "
            }
            let separator = index == 0 ? "" : " "
            text = text + Text(separator + number).foregroundStyle(CD.ink4)
                + Text(san).foregroundStyle(index == 0 ? CD.ink : CD.ink2)
                .font(index == 0 ? CDFont.bodyStrong.font : CDFont.body.font)
            ply += 1
        }
        return text.font(CDFont.body.font)
    }
}

/// The score of a line on the colour of the side it favours (`scoreTone`).
struct ScoreChip: View {
    let line: EngineLine

    var body: some View {
        Text(line.displayScore)
            .font(.custom("Geist-SemiBold", size: 13, relativeTo: .footnote))
            .cdNumber()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(width: 58, height: 26)
            .background(background, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous).strokeBorder(CD.lineStrong, lineWidth: line.tone == .black ? 1 : 0))
    }

    private var foreground: Color {
        switch line.tone {
        case .white: CD.sideBlack
        case .black: CD.sideWhite
        case .even: CD.ink
        }
    }

    private var background: Color {
        switch line.tone {
        case .white: CD.sideWhite
        case .black: CD.sideBlack
        case .even: CD.surface3
        }
    }
}

/// The moves of the analysis as PGN reads: the main line, its variations in
/// brackets after the move they replace, smaller and quieter. Tap a move to
/// go there; hold it to promote or delete its line.
struct MoveListView: View {
    let model: AnalysisBoardModel

    var body: some View {
        let tree = model.tree
        let tokens = MoveListTokens.make(tree)
        ScrollViewReader { proxy in
            ScrollView {
                if tokens.isEmpty {
                    Text("Play a move on the board to start a line.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CD.Space.s12)
                } else {
                    FlowLayout(spacing: 0, lineSpacing: 0) {
                        ForEach(tokens) { token in
                            view(for: token, in: tree)
                        }
                    }
                    .padding(.horizontal, CD.Space.s8)
                    .padding(.vertical, CD.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: model.cursor, initial: true) { _, cursor in
                withAnimation(CD.Motion.state) { proxy.scrollTo(cursor, anchor: .center) }
            }
        }
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
        .hairline()
    }

    @ViewBuilder private func view(for token: MoveListTokens.Token, in tree: MoveTree) -> some View {
        switch token.kind {
        case let .move(id, number):
            moveButton(id, number: number, depth: token.depth, tree: tree)
                .id(id)
        case .open:
            Text("(").cdFont(.small).foregroundStyle(CD.ink4).frame(minHeight: 44)
        case .close:
            Text(")").cdFont(.small).foregroundStyle(CD.ink4).frame(minHeight: 44).padding(.trailing, CD.Space.s4)
        case let .comment(text):
            Text(text)
                .cdFont(.meta)
                .italic()
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(CD.ink3)
                .padding(.horizontal, CD.Space.s4)
                .frame(minHeight: 44)
        }
    }

    private func moveButton(_ id: MoveTree.NodeID, number: String?, depth: Int, tree: MoveTree) -> some View {
        let node = tree[id]
        let selected = id == model.cursor
        let isVariation = depth > 0
        return Button {
            model.go(to: id)
        } label: {
            HStack(spacing: 2) {
                if let number {
                    Text(number).foregroundStyle(CD.ink4)
                }
                Text(node.san)
                    .foregroundStyle(selected ? CD.ink : isVariation ? CD.ink3 : CD.ink2)
            }
            .font(isVariation ? CDFont.small.font : CDFont.san.font)
            .cdNumber()
            .padding(.horizontal, CD.Space.s6)
            .frame(minHeight: 32)
            .background(selected ? CD.surface3 : .clear, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                    .strokeBorder(selected ? CD.accentLine : .clear, lineWidth: 1)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .contextMenu {
            if !tree.isOnMainLine(id) {
                Button("Make main line", systemImage: "arrow.up.to.line") { model.makeMainLine(id) }
                Button("Promote variation", systemImage: "arrow.up") { model.promote(id) }
            }
            Button("Delete from here", systemImage: "trash", role: .destructive) { model.delete(id) }
        }
        .accessibilityLabel("\(node.moveNumberText) \(node.san)\(isVariation ? ", variation" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The move list flattened for a flowing layout, in PGN order.
nonisolated enum MoveListTokens {
    struct Token: Identifiable, Hashable {
        enum Kind: Hashable {
            case move(MoveTree.NodeID, number: String?)
            case open, close
            case comment(String)
        }

        let id: Int
        let kind: Kind
        /// 0 on the main line, 1 inside a variation, and so on.
        let depth: Int
    }

    static func make(_ tree: MoveTree) -> [Token] {
        var kinds: [(Token.Kind, Int)] = []
        walk(tree, after: tree.root, forceNumber: true, depth: 0, into: &kinds)
        return kinds.enumerated().map { Token(id: $0.offset, kind: $0.element.0, depth: $0.element.1) }
    }

    private static func walk(
        _ tree: MoveTree,
        after parent: MoveTree.NodeID,
        forceNumber: Bool,
        depth: Int,
        into kinds: inout [(Token.Kind, Int)]
    ) {
        let children = tree[parent].children
        guard let main = children.first else { return }
        emit(tree, main, forceNumber: forceNumber, depth: depth, into: &kinds)
        for variation in children.dropFirst() {
            kinds.append((.open, depth + 1))
            emit(tree, variation, forceNumber: true, depth: depth + 1, into: &kinds)
            walk(tree, after: variation, forceNumber: tree[variation].comment != nil, depth: depth + 1, into: &kinds)
            kinds.append((.close, depth + 1))
        }
        walk(tree, after: main, forceNumber: children.count > 1 || tree[main].comment != nil, depth: depth, into: &kinds)
    }

    private static func emit(
        _ tree: MoveTree,
        _ id: MoveTree.NodeID,
        forceNumber: Bool,
        depth: Int,
        into kinds: inout [(Token.Kind, Int)]
    ) {
        let node = tree[id]
        let number = node.side == .white || forceNumber ? node.moveNumberText : nil
        kinds.append((.move(id, number: number), depth))
        if let comment = node.comment { kinds.append((.comment(comment), depth)) }
    }
}

/// Lays its children in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
