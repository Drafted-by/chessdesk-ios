import ChessCore
import SwiftUI

/// Today's Daily 5, full screen (the site's `/train/daily`): opens straight
/// on the first position and ends on the streak. A working screen.
struct DailyScreen: View {
    /// Called when the player leaves; with `.progress` to see the progress next.
    let close: (HomeRoute?) -> Void

    @Environment(AppModel.self) private var app
    @State private var model: DailySessionModel?

    var body: some View {
        Group {
            if let model {
                DailyContent(model: model, close: close)
            } else {
                LoadingView()
            }
        }
        .overlay(alignment: .topLeading) {
            Button { close(nil) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CD.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .padding(.leading, CD.Space.s4)
        }
        .background(CD.canvas.ignoresSafeArea())
        .task {
            guard model == nil, let token = app.token else { return }
            let fresh = DailySessionModel(api: app.api, token: token)
            model = fresh
            await fresh.load()
        }
    }
}

private struct DailyContent: View {
    let model: DailySessionModel
    let close: (HomeRoute?) -> Void

    /// The player tapped Finish on the last position.
    @State private var showsSummary = false

    var body: some View {
        content
        #if DEBUG
        .task { await autoplay() }
        #endif
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .failed(message):
            LoadFailureView(title: "The Daily 5 did not load", message: message) {
                Task { await model.load() }
            }
        case .empty:
            message(
                title: "Nothing to solve right now",
                text: "No positions are available right now. Review a game to fill your mistake bank.",
                again: false
            )
        case .doneEarlier:
            message(
                title: "Today's Daily 5 is done",
                text: "The next one opens tomorrow. Keep going with the rest of your plan, or run five more now (it will not count twice).",
                again: true
            )
        case .solving, .closing, .finished, .closeFailed:
            if showsSummary {
                DailySummary(model: model, close: close)
            } else {
                PositionTrainerView(model: model, finish: { showsSummary = true })
            }
        }
    }

    #if DEBUG
        /// `-CDDailyAutoplay YES` solves the session unattended (the second
        /// position with "Show me"), to look at its end in the simulator.
        private func autoplay() async {
            guard UserDefaults.standard.bool(forKey: "CDDailyAutoplay") else { return }
            while model.phase == .loading { try? await Task.sleep(for: .milliseconds(200)) }
            while model.phase == .solving || model.phase == .closing, let expected = model.drill.expected {
                try? await Task.sleep(for: .milliseconds(500))
                if model.drill.index == 1 { model.drill.reveal() }
                model.play(expected)
                await model.pending?.value
                if model.drill.isLast { break }
                model.drill.next()
            }
            showsSummary = true
        }
    #endif

    private func message(title: String, text: String, again: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text(title)
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(text)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if again {
                    Button("Back to today") { close(nil) }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    Button("Five more") { Task { await model.load(again: true) } }
                        .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                } else {
                    Button("Pick a game to review") { close(.games) }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                }
                if let streak = model.streak {
                    CDCard { StreakStats(streak: streak) }
                }
            }
            .pageGutter()
            .padding(.top, 56)
            .padding(.bottom, CD.Space.s32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One position after the other (the site's `PositionTrainer`).
private struct PositionTrainerView: View {
    let model: DailySessionModel
    let finish: () -> Void

    @State private var wrongMove: Move?

    var body: some View {
        let drill = model.drill
        if let item = drill.item, let start = drill.start {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                progressLine(drill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)

                // The board and its question in the middle of what is left.
                Spacer(minLength: 0)

                BoardView(
                    position: shownPosition(drill, start: start),
                    orientation: start.turn,
                    lastMove: drill.feedback == .correct ? drill.expected : wrongMove,
                    arrows: drill.feedback == .revealed ? bestArrow(drill) : [],
                    verdict: verdict(drill),
                    movableSide: drill.feedback == .correct ? nil : start.turn,
                    onMove: play
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    eyebrow(item)
                    Text("\(start.turn == .white ? "White" : "Black") to play. Find the best move.")
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                    if let played = item.playedSan, let label = item.moveLabel {
                        Text("In the game you played \(label) \(played) here.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    feedback(drill, item: item)
                }
                .pageGutter()

                Spacer(minLength: 0)

                Group {
                    if drill.feedback == .correct {
                        Button(drill.isLast ? "Finish" : "Next position") {
                            if drill.isLast { finish() } else { next() }
                        }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    } else {
                        Button("Show me") {
                            wrongMove = nil
                            model.drill.reveal()
                        }
                        .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                    }
                }
                .pageGutter()
                .padding(.bottom, CD.Space.s16)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func progressLine(_ drill: PositionDrill) -> some View {
        HStack(spacing: CD.Space.s8) {
            Text("Daily 5: position \(drill.index + 1) of \(drill.items.count)")
            Text("·").foregroundStyle(CD.ink4)
            Text("\(drill.solvedFirstTry) first try")
        }
        .cdFont(.small)
        .foregroundStyle(CD.ink3)
        .cdNumber()
        .accessibilityElement(children: .combine)
    }

    private func eyebrow(_ item: TrainItem) -> some View {
        HStack(spacing: CD.Space.s6) {
            Text(kindLabel(item))
                .foregroundStyle(item.classification?.value == .blunder ? CD.loss : CD.ink2)
            Text("·").foregroundStyle(CD.ink4)
            Text(item.label)
                .lineLimit(1)
            if item.kind.value == .mistake, !item.firstTime {
                Spacer(minLength: CD.Space.s8)
                CDBadge(text: "Seen before")
            }
        }
        .cdFont(.meta)
        .foregroundStyle(CD.ink3)
    }

    private func kindLabel(_ item: TrainItem) -> String {
        switch item.kind.value {
        case .mistake: item.classification?.value == .blunder ? "Blunder" : "Mistake"
        case .puzzle: "Puzzle"
        case .study: "Study"
        case nil: "Position"
        }
    }

    @ViewBuilder private func feedback(_ drill: PositionDrill, item: TrainItem) -> some View {
        Group {
            switch drill.feedback {
            case .idle:
                Text("Look for checks, captures and threats first.")
                    .foregroundStyle(CD.ink3)
            case .wrong:
                Text("Not the best move. Look again: checks, captures, threats.")
                    .foregroundStyle(CD.loss)
            case .correct:
                Text("Yes, \(item.bestSan).")
                    .foregroundStyle(CD.win)
            case .revealed:
                Text("The move is \(item.bestSan). Play it on the board to lock it in.")
                    .foregroundStyle(CD.accentStrong)
            }
        }
        .cdFont(.small)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func shownPosition(_ drill: PositionDrill, start: Position) -> Position {
        if drill.feedback == .correct, let expected = drill.expected, let after = start.playing(expected) { return after }
        if let wrongMove, let after = start.playing(wrongMove) { return after }
        return start
    }

    private func verdict(_ drill: PositionDrill) -> BoardVerdict? {
        if drill.feedback == .correct, let expected = drill.expected { return BoardVerdict(square: expected.to, kind: .right) }
        if let wrongMove { return BoardVerdict(square: wrongMove.to, kind: .wrong) }
        return nil
    }

    private func bestArrow(_ drill: PositionDrill) -> [BoardArrow] {
        drill.expected.map { [BoardArrow(from: $0.from, to: $0.to, brush: .move)] } ?? []
    }

    /// A wrong move is shown for a moment, then taken back (the site's wrong-move flash).
    private func play(_ move: Move) -> Bool {
        guard wrongMove == nil else { return false }
        switch model.play(move) {
        case .ignored:
            return false
        case .wrong:
            wrongMove = move
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                wrongMove = nil
            }
            return true
        case .resolved:
            wrongMove = nil
            return true
        }
    }

    private func next() {
        wrongMove = nil
        model.drill.next()
    }
}

/// The end of the session: the streak as the server moved it, and the
/// reminder offer when the server asks for it (`DailyDone` of `daily-session.tsx`).
private struct DailySummary: View {
    let model: DailySessionModel
    let close: (HomeRoute?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                switch model.phase {
                case let .finished(result):
                    finished(result)
                case let .closeFailed(message):
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        Text("Your answers are saved, but the session could not be closed.")
                            .cdFont(.body)
                            .foregroundStyle(CD.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try again") { Task { await model.close() } }
                            .buttonStyle(.cd(.primary, fullWidth: true))
                    }
                default:
                    HStack(spacing: CD.Space.s12) {
                        ProgressView().tint(CD.ink3)
                        Text("Saving your session…").cdFont(.body).foregroundStyle(CD.ink2)
                    }
                }
            }
            .pageGutter()
            .padding(.top, 56)
            .padding(.bottom, CD.Space.s32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func finished(_ result: DailyCompletion) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text("Daily 5 done")
                .cdFont(.pageTitle)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            Text(summary(result))
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        CDCard {
            Grid(alignment: .leading, horizontalSpacing: CD.Space.s16, verticalSpacing: CD.Space.s12) {
                GridRow {
                    figure("Streak", CDFormat.plural(result.streak, "day"))
                    figure("Longest", CDFormat.plural(result.longest, "day"))
                }
                GridRow {
                    figure("Freeze days", "\(result.freezes) of \(StreakStats.maxFreezes)")
                    figure("Positions", CDFormat.count(model.drill.items.count))
                }
            }
        }
        if let offer = model.reminderOffer {
            ReminderOfferCard(offer: offer, hour: model.offerHour, accept: {
                Task { await model.acceptReminder() }
            }, dismiss: {
                Task { await model.dismissReminder() }
            })
        }
        let offerOpen = model.reminderOffer == .offered || model.reminderOffer == .failed
        Button("Back to today") { close(nil) }
            .buttonStyle(.cd(offerOpen ? .secondary : .primary, size: .large, fullWidth: true))
        Button("See your progress") { close(.progress) }
            .buttonStyle(.cd(.ghost, fullWidth: true))
    }

    private func summary(_ result: DailyCompletion) -> String {
        var notes = [result.counted ? "Day \(max(1, result.streak)) of your streak." : "Today already counted: this one does not count twice."]
        if result.freezeUsed > 0 {
            notes.append("A freeze day covered \(result.freezeUsed == 1 ? "the day" : "the \(result.freezeUsed) days") you missed.")
        }
        if result.earnedFreeze { notes.append("You earned a freeze day: it covers one missed day automatically.") }
        return notes.joined(separator: " ")
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s2) {
            Text(label).cdFont(.meta).foregroundStyle(CD.ink3)
            Text(value).cdFont(.cardTitle).foregroundStyle(CD.ink).cdNumber()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Same time tomorrow?": one email a day at this hour (`reminder-offer.tsx`).
/// The site's other channel is a browser notification, which the app cannot
/// set up; the app offers email only.
private struct ReminderOfferCard: View {
    let offer: DailySessionModel.ReminderOffer
    let hour: Int
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        switch offer {
        case .dismissed:
            EmptyView()
        case let .set(hour):
            Label("Reminder set for \(ReminderHour.label(hour)) by email. Change it any time in You.", systemImage: "checkmark")
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        case .offered, .saving, .failed:
            CDCard {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text("Same time tomorrow?")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                        Text("One short email a day at \(ReminderHour.label(hour)), with a link straight to your first position. Stop it any time.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Email me at \(ReminderHour.label(hour))", action: accept)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                        .disabled(offer == .saving)
                    Button("Not now", action: dismiss)
                        .buttonStyle(.cd(.ghost, fullWidth: true))
                        .disabled(offer == .saving)
                    if offer == .failed {
                        Text("Could not save the reminder. Try again from You.")
                            .cdFont(.small)
                            .foregroundStyle(CD.loss)
                    }
                }
            }
        }
    }
}

/// "18:00": the site's `hourLabel`.
nonisolated enum ReminderHour {
    static func label(_ hour: Int) -> String {
        hour < 10 ? "0\(hour):00" : "\(hour):00"
    }
}
