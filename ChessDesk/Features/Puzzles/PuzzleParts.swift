import Charts
import ChessCore
import SwiftUI

/// Routes of the puzzles section.
enum PuzzlesRoute: Hashable {
    case free, rated, woodpecker
}

// MARK: Trainer pieces

/// One number of a trainer's strip: a label, the value, a line under it.
struct TrainerStat: View {
    let label: String
    let value: String
    var detail: String?
    var accent = false
    var delta: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s6) {
                Text(value)
                    .cdFont(.sectionTitle)
                    .foregroundStyle(accent ? CD.accentStrong : CD.ink)
                    .cdNumber()
                if let delta {
                    Text(delta > 0 ? "+\(delta)" : delta < 0 ? "−\(-delta)" : "±0")
                        .cdFont(.meta)
                        .foregroundStyle(delta > 0 ? CD.win : delta < 0 ? CD.loss : CD.ink3)
                        .cdNumber()
                }
            }
            if let detail {
                Text(detail)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink4)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Whose move it is, and a fact about the puzzle.
struct TurnLine: View {
    let side: Side
    var meta: String?

    var body: some View {
        HStack(spacing: CD.Space.s8) {
            SideSwatch(side: side, size: 11)
            Text("\(side == .white ? "White" : "Black") to move")
                .cdFont(.bodyStrong)
                .foregroundStyle(CD.ink)
            Spacer(minLength: CD.Space.s8)
            if let meta {
                Text(meta)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The trainer's answer in words, coloured only when it carries meaning.
struct TrainerNotice: View {
    enum Tone { case neutral, right, wrong, caution }

    let tone: Tone
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            (Text(title).foregroundStyle(tone == .neutral ? CD.ink : color)
                + Text(detail.map { " \($0)" } ?? "").foregroundStyle(CD.ink2))
                .cdFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch tone {
        case .neutral: "scope"
        case .right: "checkmark"
        case .wrong: "xmark"
        case .caution: "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .neutral: CD.ink3
        case .right: CD.win
        case .wrong: CD.loss
        case .caution: CD.caution
        }
    }
}

/// A filter choice: 44 pt tall, quiet until chosen.
struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Geist-Medium", size: 13.5, relativeTo: .subheadline))
                .foregroundStyle(selected ? CD.ink : CD.ink3)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selected ? CD.surface3 : .clear, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                        .strokeBorder(selected ? CD.lineHover : CD.line, lineWidth: 1)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A menu that reads as a filter: the current choice and a chevron.
struct FilterMenuLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: CD.Space.s6) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .font(.custom("Geist-Medium", size: 13.5, relativeTo: .subheadline))
        .foregroundStyle(CD.ink2)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous).strokeBorder(CD.line, lineWidth: 1))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The board of a trainer, at the width a phone allows.
struct PuzzleBoardView: View {
    let board: PuzzleBoard?
    let orientation: Side
    var hint: Square?
    let movableSide: Side?
    let onMove: (Move) -> Bool

    var body: some View {
        Group {
            if let board {
                BoardView(
                    position: board.position,
                    orientation: orientation,
                    lastMove: board.lastMove,
                    verdict: board.verdict,
                    hint: hint,
                    movableSide: movableSide,
                    onMove: onMove
                )
            } else {
                RoundedRectangle(cornerRadius: CD.Radius.sm).fill(CD.surface1)
                    .overlay(ProgressView().tint(CD.ink3))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Results

/// The rating over the last puzzles: one brass line, the last point marked.
struct RatingCurve: View {
    let points: [PuzzlePlayer.Point]

    var body: some View {
        let ratings = points.map(\.rating)
        let low = (ratings.min() ?? 0) - 15
        let high = (ratings.max() ?? 0) + 15
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                LineMark(x: .value("Puzzle", index), y: .value("Rating", point.rating))
                    .foregroundStyle(CD.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Puzzle", points.count - 1), y: .value("Rating", last.rating))
                    .foregroundStyle(CD.accent)
                    .symbolSize(64)
            }
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: low...high)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(CD.line)
                AxisValueLabel().font(.custom("Geist-Regular", size: 11)).foregroundStyle(CD.ink4)
            }
        }
        .frame(height: 120)
        .accessibilityElement()
        .accessibilityLabel(
            "Puzzle rating over the last \(points.count) puzzles, from \(ratings.first ?? 0) to \(ratings.last ?? 0)."
        )
    }
}

/// Completed cycles against their halving targets. The bars share one scale.
struct CycleTable: View {
    let cycles: [WoodpeckerCycle]

    var body: some View {
        if cycles.isEmpty {
            Text("No completed cycles yet.")
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
        } else {
            let slowest = max(1, cycles.map(\.durationMs).max() ?? 1)
            VStack(spacing: 0) {
                header
                ForEach(cycles) { cycle in
                    CDHairline()
                    row(cycle, slowest: slowest)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: CD.Space.s8) {
            Text("Cycle").frame(width: 58, alignment: .leading)
            Spacer(minLength: 0)
            Text("Time").frame(width: 62, alignment: .trailing)
            Text("Target").frame(width: 56, alignment: .trailing)
            Text("Right").frame(width: 46, alignment: .trailing)
        }
        .cdFont(.meta)
        .foregroundStyle(CD.ink3)
        .padding(.bottom, CD.Space.s6)
    }

    private func row(_ cycle: WoodpeckerCycle, slowest: Int) -> some View {
        HStack(spacing: CD.Space.s8) {
            Text("Cycle \(cycle.cycleNumber)")
                .foregroundStyle(CD.ink2)
                .frame(width: 58, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(CD.surface3).frame(height: 4)
                    Capsule().fill(CD.ink3)
                        .frame(width: proxy.size.width * CGFloat(cycle.durationMs) / CGFloat(slowest), height: 4)
                    if let target = cycle.targetMs {
                        Rectangle().fill(CD.accent)
                            .frame(width: 2, height: 10)
                            .offset(x: min(proxy.size.width - 2, proxy.size.width * CGFloat(target) / CGFloat(slowest)))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            HStack(spacing: 4) {
                if cycle.targetBeaten == true {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CD.win)
                        .accessibilityLabel("Target beaten")
                }
                Text(WoodpeckerFormat.time(cycle.durationMs)).foregroundStyle(CD.ink)
            }
            .frame(width: 62, alignment: .trailing)
            Text(cycle.targetMs.map(WoodpeckerFormat.time) ?? "–")
                .foregroundStyle(CD.ink3)
                .frame(width: 56, alignment: .trailing)
            Text("\(Int((cycle.accuracy * 100).rounded()))%")
                .foregroundStyle(CD.ink2)
                .frame(width: 46, alignment: .trailing)
        }
        .cdFont(.small)
        .cdNumber()
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The page of this section: gutter, readable width.
    func puzzlesPage() -> some View {
        pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}
