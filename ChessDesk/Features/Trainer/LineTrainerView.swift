import ChessCore
import SwiftUI

/// One line on screen: the board, the move strip, the reading plate and the
/// transport. A chess book, not a form.
struct LineTrainerView: View {
    /// What the last button leads to once the line is done.
    enum Following { case nextInSession, nextLine, locked, none }

    let label: String
    let chapter: String?
    let narration: Narration?
    let following: Following
    let onGrades: ([MoveGrade]) -> Void
    let onFollow: () -> Void
    let close: () -> Void

    @State private var model: LineTrainerModel
    @Environment(NarrationPlayer.self) private var voice
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(
        line: TrainingLine,
        side: Side,
        review: [Int]?,
        label: String,
        chapter: String?,
        narration: Narration?,
        following: Following,
        onGrades: @escaping ([MoveGrade]) -> Void,
        onFollow: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.label = label
        self.chapter = chapter
        self.narration = narration
        self.following = following
        self.onGrades = onGrades
        self.onFollow = onFollow
        self.close = close
        _model = State(initialValue: LineTrainerModel(line: line, side: side, review: review))
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = sizeClass == .regular && proxy.size.width > proxy.size.height
            Group {
                if wide {
                    HStack(spacing: 0) {
                        board
                            .padding(CD.Space.s24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle().fill(CD.line).frame(width: 1)
                        panel.frame(width: min(460, proxy.size.width * 0.4))
                    }
                } else {
                    VStack(spacing: 0) {
                        board.frame(maxWidth: sizeClass == .regular ? 620 : .infinity)
                        panel
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
        }
        .onAppear {
            model.onMovePlayed = { BoardSounds.shared.play(capture: $0) }
            model.onFinished = { onGrades($0) }
            model.start()
            #if DEBUG
                if DebugLaunch.trainerMemory {
                    model.startMemoryPass()
                } else {
                    for _ in 0..<DebugLaunch.trainerSteps { model.next() }
                }
            #endif
            speakLead()
        }
        .onDisappear { model.stop() }
        .onChange(of: model.cursor) { _, _ in speakLead() }
        .onChange(of: model.phase) { _, _ in speakLead() }
        .onChange(of: model.noteRevealed) { _, revealed in
            if revealed { speakLead() }
        }
    }

    private func speakLead() {
        guard let step = model.leadStep else {
            voice.stop()
            return
        }
        voice.speak(step.comments, narration: narration)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: CD.Space.s8) {
            Color.clear.frame(width: 44, height: 44)
            VStack(spacing: 1) {
                Text(label)
                    .cdFont(.cardTitle)
                    .foregroundStyle(CD.ink)
                if let chapter {
                    Text(chapter)
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            if narration != nil {
                Button {
                    voice.isEnabled.toggle()
                    if voice.isEnabled { speakLead() }
                } label: {
                    Image(systemName: voice.isEnabled ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(voice.isEnabled ? CD.ink2 : CD.ink4)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(voice.isEnabled ? "Turn narration off" : "Turn narration on")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, CD.Space.s4)
        .background(CD.canvas)
    }

    // MARK: Board

    private var board: some View {
        BoardView(
            position: model.position,
            orientation: model.side,
            lastMove: model.lastMove,
            arrows: model.arrows,
            verdict: model.verdict,
            hint: model.hintSquare,
            movableSide: model.isOurTurn && model.phase != .finished ? model.side : nil,
            onMove: { model.play($0) }
        )
        .animation(CD.Motion.state, value: model.verdict)
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            MoveStrip(model: model)
            CDHairline()
            ScrollView {
                plate
                    .padding(.horizontal, CD.Space.s20)
                    .padding(.vertical, CD.Space.s20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            transport
        }
        .background(CD.canvas)
    }

    @ViewBuilder private var plate: some View {
        switch model.phase {
        case .guided:
            if model.guidedPassDone {
                PlateMessage(
                    title: "That is the whole line",
                    text: "Now play it from memory. The other side replies by itself, and a move you hesitate on comes back sooner."
                )
            } else if let step = model.currentStep {
                ReadingPlate(step: step, trailing: model.trailingStep, side: model.side)
            }
        case .play:
            if let step = model.leadStep {
                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    if model.feedback == .missed {
                        Label("Not this move. Here is the idea again.", systemImage: "arrow.uturn.backward")
                            .cdFont(.small)
                            .foregroundStyle(CD.loss)
                    }
                    ReadingPlate(step: step, trailing: nil, side: model.side, hidesMove: true)
                }
            } else {
                PlateMessage(
                    title: model.isOurTurn ? "Your move" : "…",
                    text: model.isReview
                        ? "Play the move from your repertoire."
                        : "Play the move you just learned. Ask for a hint if it will not come."
                )
            }
        case .finished:
            FinishedPlate(model: model)
        }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: CD.Space.s12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(CD.line)
                    Rectangle().fill(CD.ink4).frame(width: proxy.size.width * model.progress)
                }
            }
            .frame(height: 1)
            .animation(CD.Motion.state, value: model.progress)

            HStack(alignment: .firstTextBaseline) {
                Text(instruction)
                    .cdFont(.small)
                    .foregroundStyle(model.feedback == .notThisOne ? CD.accentStrong : CD.ink3)
                    .lineLimit(2)
                Spacer(minLength: CD.Space.s12)
                Text(count)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink4)
                    .cdNumber()
                    .layoutPriority(1)
            }
            .padding(.horizontal, CD.Space.s16)

            buttons
                .padding(.horizontal, CD.Space.s16)
                .padding(.bottom, CD.Space.s8)
        }
        .background(CD.surface1.ignoresSafeArea(edges: .bottom))
    }

    private var instruction: String {
        switch model.phase {
        case .guided:
            if model.guidedPassDone { return "Ready when you are." }
            if model.feedback == .notThisOne { return "Not this one: the arrow shows the move." }
            let other = model.side == .white ? "Black" : "White"
            return model.currentStep?.mine == true
                ? "Play it on the board. \(other) replies by itself."
                : "\(other) is playing."
        case .play:
            return model.isOurTurn ? "Hinted moves come back sooner." : "Wait for the reply."
        case .finished:
            return model.missedCount == 0 ? "Every move from memory." : "Missed moves come back sooner."
        }
    }

    private var count: String {
        switch model.phase {
        case .guided:
            "Step \(min(model.cursor + 1, model.steps.count)) of \(model.steps.count)"
        case .play, .finished:
            "Move \(min(model.ourMovesPlayed + 1, model.ourMoveCount)) of \(model.ourMoveCount)"
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.phase {
        case .guided where model.guidedPassDone:
            HStack(spacing: CD.Space.s8) {
                Button("Learn it again") { model.learnAgain() }
                    .buttonStyle(.cd(.ghost))
                Button("Play it from memory") { model.startMemoryPass() }
                    .buttonStyle(.cd(.primary, fullWidth: true))
            }
        case .guided:
            HStack(spacing: CD.Space.s8) {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.cd(.secondary))
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back to my previous move")

                Button("Next move") { model.next() }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                    .disabled(model.isBoardLocked)

                Button("Skip to practice") { model.startMemoryPass() }
                    .buttonStyle(.cd(.ghost))
                    .fixedSize()
            }
        case .play:
            HStack(spacing: CD.Space.s8) {
                Button(model.hintLevel == 0 ? "Hint" : "Show the move") { model.hint() }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                    .disabled(!model.isOurTurn || model.hintLevel >= 2)
                Button("Read the note") { model.revealNote() }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                    .disabled(!model.isOurTurn || model.noteRevealed)
            }
        case .finished:
            VStack(spacing: CD.Space.s8) {
                switch following {
                case .nextInSession, .nextLine:
                    Button("Next line", action: onFollow)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                case .locked:
                    Button(action: onFollow) {
                        Label("Next line", systemImage: "lock")
                    }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                case .none:
                    Button("Done", action: close)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                }
                HStack(spacing: CD.Space.s8) {
                    if !model.isReview {
                        Button("Learn it again") { model.learnAgain() }
                            .buttonStyle(.cd(.ghost, fullWidth: true))
                    }
                    if following != .none {
                        Button("Done", action: close)
                            .buttonStyle(.cd(.ghost, fullWidth: true))
                    }
                }
            }
        }
    }
}

// MARK: Reading plate

/// The note before its move: the move as a serif heading, the side, a
/// hairline, then the note. Typographic, not a box.
private struct ReadingPlate: View {
    let step: LineStep
    let trailing: LineStep?
    let side: Side
    var hidesMove = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            if !hidesMove {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(step.numberLabel)
                        .font(.custom("Newsreader72pt-Regular", size: 26, relativeTo: .title2))
                        .foregroundStyle(CD.ink4)
                        .cdNumber()
                    Text(step.san)
                        .font(.custom("Newsreader72pt-Medium", size: 26, relativeTo: .title2))
                        .foregroundStyle(CD.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                HStack(spacing: CD.Space.s6) {
                    SideSwatch(side: moverSide)
                    Text("\(moverSide == .white ? "White" : "Black") · \(step.mine ? "your move" : "the reply")")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                }
                CDHairline()
            }

            if step.comments.isEmpty {
                Text(step.mine ? "Play \(step.san)." : "The reply is \(step.san).")
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink3)
            } else {
                ForEach(Array(step.comments.enumerated()), id: \.offset) { _, comment in
                    Text(comment)
                        .font(.custom("Newsreader16pt-Regular", size: sizeClass == .regular ? 21 : 19, relativeTo: .body))
                        .lineSpacing(6)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let trailing {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("\(trailing.numberLabel) \(trailing.san)")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink4)
                        .cdNumber()
                    Text(trailing.note)
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, CD.Space.s8)
            }
        }
        .frame(maxWidth: 36 * 19, alignment: .leading)
    }

    private var moverSide: Side { step.mine ? side : side.opposite }
}

private struct PlateMessage: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text(title)
                .cdFont(.plateTitle)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FinishedPlate: View {
    let model: LineTrainerModel

    var body: some View {
        let total = model.grades.count
        let good = model.grades.count { $0.grade == .good }
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            Text(model.isReview ? "Line reviewed" : "Line learned")
                .cdFont(.plateTitle)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                Text("\(good)")
                    .cdFont(.metric)
                    .foregroundStyle(CD.ink)
                    .cdNumber()
                Text("of \(CDFormat.plural(total, "move")) from memory")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
            }
            .accessibilityElement(children: .combine)
            CDMeter(value: total == 0 ? 0 : Double(good) / Double(total), tint: CD.win, height: 5)
            Text(
                good == total
                    ? "It goes into your reviews and comes back just before you would forget it."
                    : "The moves you missed come back first, until they stick."
            )
            .cdFont(.lede)
            .foregroundStyle(CD.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Move strip

/// The line as one row of moves that follows the current one. In the guided
/// pass the moves to come are shown dimmed; from memory, only the moves played.
private struct MoveStrip: View {
    let model: LineTrainerModel

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, step in
                        if step.ply % 2 == 1 || index == 0 {
                            Text(index == 0 && step.ply % 2 == 0 ? "\((step.ply + 1) / 2)…" : "\((step.ply + 1) / 2).")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink4)
                                .cdNumber()
                                .padding(.leading, index == 0 ? 0 : CD.Space.s8)
                        }
                        chip(step, index: index).id(index)
                    }
                    if model.phase == .play, model.currentStep != nil {
                        RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous)
                            .strokeBorder(CD.accentLine, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 34, height: 26)
                            .id(-1)
                            .accessibilityLabel("Move to find")
                    }
                }
                .padding(.horizontal, CD.Space.s16)
            }
            .frame(height: 44)
            .onChange(of: model.cursor, initial: true) { _, cursor in
                withAnimation(CD.Motion.state) {
                    reader.scrollTo(model.phase == .play ? -1 : min(cursor, model.steps.count - 1), anchor: .center)
                }
            }
        }
    }

    private var visible: [LineStep] {
        model.phase == .guided ? model.steps : Array(model.steps.prefix(model.cursor))
    }

    private func chip(_ step: LineStep, index: Int) -> some View {
        let isCurrent = model.phase == .guided && index == model.cursor
        let isPlayed = index < model.cursor
        return Text(step.san)
            .font(.custom(step.mine && isPlayed ? "Geist-SemiBold" : "Geist-Medium", size: 14.5, relativeTo: .subheadline))
            .cdNumber()
            .foregroundStyle(isCurrent ? CD.accentStrong : isPlayed ? (step.mine ? CD.ink : CD.ink2) : CD.ink4)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(
                isCurrent ? CD.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous)
                    .strokeBorder(isCurrent ? CD.accentLine : .clear, lineWidth: 1)
            )
    }
}
