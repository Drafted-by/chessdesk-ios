import ChessCore
import SwiftUI

/// One line on screen: the board, the move strip, the reading plate and the
/// transport. A chess book, not a form.
struct LineTrainerView: View {
    /// What the last button leads to once the line is done.
    enum Following { case nextInSession, nextLine, locked, none }

    let label: String
    let chapter: String?
    /// Learning paths: what the learner is asked in this exercise.
    let task: String?
    let narration: Narration?
    let following: Following
    /// What the button that leads on says: "Next line", "Next exercise"…
    let followTitle: String
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
        flow: ExerciseFlow = .learn,
        task: String? = nil,
        judge: (any MoveJudging)? = nil,
        label: String,
        chapter: String?,
        narration: Narration?,
        following: Following,
        followTitle: String = "Next line",
        onGrades: @escaping ([MoveGrade]) -> Void,
        onFollow: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.label = label
        self.chapter = chapter
        self.task = task
        self.narration = narration
        self.following = following
        self.followTitle = followTitle
        self.onGrades = onGrades
        self.onFollow = onFollow
        self.close = close
        let model = LineTrainerModel(line: line, side: side, review: review, flow: flow)
        model.judge = judge
        _model = State(initialValue: model)
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

    /// What is read aloud now: the task when an exercise opens, the note of
    /// the move about to be played, or why the move just found works.
    private func speakLead() {
        var texts: [String] = []
        let opening = model.cursor == 0 || (model.flow == .solve && model.solvedStep == nil)
        if let task, opening, model.phase != .finished { texts.append(task) }
        if model.flow == .solve {
            if model.phase == .play, model.feedback == nil, let solved = model.solvedStep {
                texts = solved.comments
            }
        } else if let step = model.leadStep {
            texts += step.comments
        }
        if texts.isEmpty {
            voice.stop()
        } else {
            voice.speak(texts, narration: narration)
        }
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
                VStack(alignment: .leading, spacing: CD.Space.s20) {
                    if let task, model.cursor == 0 {
                        Text(task)
                            .cdFont(.lede)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        CDHairline()
                    }
                    ReadingPlate(step: step, trailing: model.trailingStep, side: model.side)
                }
            }
        case .play where model.flow == .solve:
            SolvePlate(model: model, task: task)
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
        case .play where model.flow == .solve:
            if model.isJudging { return "Checking your move." }
            return model.isOurTurn ? "Stuck? A hint shows the piece, then the move." : "Wait for the reply."
        case .play:
            return model.isOurTurn ? "Hinted moves come back sooner." : "Wait for the reply."
        case .finished:
            if model.flow == .lesson { return "Played through." }
            if model.flow == .solve { return model.missedCount == 0 ? "Found at the first try." : "Found." }
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

    private var again: String {
        switch model.flow {
        case .learn: "Learn it again"
        case .lesson: "Play it again"
        case .solve: "Solve it again"
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

                if model.flow != .lesson {
                    Button("Skip to practice") { model.startMemoryPass() }
                        .buttonStyle(.cd(.ghost))
                        .fixedSize()
                }
            }
        case .play:
            HStack(spacing: CD.Space.s8) {
                Button(model.hintLevel == 0 ? "Hint" : "Show the move") { model.hint() }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                    .disabled(!model.isOurTurn || model.hintLevel >= 2)
                if model.flow != .solve {
                    Button("Read the note") { model.revealNote() }
                        .buttonStyle(.cd(.secondary, fullWidth: true))
                        .disabled(!model.isOurTurn || model.noteRevealed)
                }
            }
        case .finished:
            VStack(spacing: CD.Space.s8) {
                switch following {
                case .nextInSession, .nextLine:
                    Button(followTitle, action: onFollow)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                case .locked:
                    Button(action: onFollow) {
                        Label(followTitle, systemImage: "lock")
                    }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                case .none:
                    Button("Done", action: close)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                }
                HStack(spacing: CD.Space.s8) {
                    if !model.isReview {
                        Button(again) { model.learnAgain() }
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
            Text(title)
                .cdFont(.plateTitle)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            if model.flow != .learn {
                // A path exercise is done once: no score to beat, the idea to keep.
                if model.solvedAnotherWay {
                    Text("Your move works just as well as the one in the course.")
                        .cdFont(.small)
                        .foregroundStyle(CD.win)
                }
                if let takeaway = model.steps.last(where: { !$0.comments.isEmpty })?.note {
                    Text(takeaway)
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
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

    private var title: String {
        switch model.flow {
        case .lesson: "Lesson done"
        case .solve: "Solved"
        case .learn: model.isReview ? "Line reviewed" : "Line learned"
        }
    }
}

/// A position to solve: the task, then why the move works once it is found.
private struct SolvePlate: View {
    let model: LineTrainerModel
    let task: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            if model.isJudging {
                Label("Checking your move with the engine", systemImage: "cpu")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            } else if model.feedback == .missed {
                Label("Not this move. Look again.", systemImage: "arrow.uturn.backward")
                    .cdFont(.small)
                    .foregroundStyle(CD.loss)
            }
            if let solved = model.solvedStep, model.feedback == nil, !solved.comments.isEmpty {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("Why \(solved.san) works")
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.win)
                    Text(solved.note)
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    HStack(spacing: CD.Space.s6) {
                        SideSwatch(side: model.side)
                        Text("\(model.side == .white ? "White" : "Black") to play")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                    }
                    Text(task ?? "Find the best move.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
