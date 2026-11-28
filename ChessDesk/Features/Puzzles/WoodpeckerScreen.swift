import ChessCore
import SwiftUI

/// The Woodpecker Method. The server says which screen to show; this view
/// draws it: the way in (discovery, Premium, calibration, a new set), a
/// cycle being solved, the pause between two cycles, the report of a set.
struct WoodpeckerScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: WoodpeckerModel?
    @State private var signIn: SignInView.Mode?

    var body: some View {
        Group {
            if !app.isSignedIn {
                ScrollView {
                    VStack(alignment: .leading, spacing: CD.Space.s16) {
                        Text(WoodpeckerCopy.method)
                            .cdFont(.lede)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        AccountPitch(signIn: $signIn, title: "Woodpecker needs an account")
                    }
                    .puzzlesPage()
                }
            } else if let model {
                WoodpeckerContent(model: model)
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Woodpecker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .sheet(item: $signIn) { SignInView(mode: $0) }
        .task(id: app.accountRevision) {
            guard app.isSignedIn else {
                model = nil
                return
            }
            let fresh = WoodpeckerModel(api: app.api, token: { [app] in app.token })
            model = fresh
            await fresh.load()
        }
    }
}

private struct WoodpeckerContent: View {
    @Bindable var model: WoodpeckerModel

    var body: some View {
        Group {
            switch model.screen {
            case .loading:
                LoadingView()
            case let .failed(message):
                LoadFailureView(title: "Woodpecker did not load", message: message) {
                    Task { await model.load() }
                }
            case .entry:
                if let overview = model.overview {
                    WoodpeckerEntry(model: model, overview: overview)
                }
            case .solving:
                WoodpeckerSolving(model: model)
            case .between:
                if let run = model.run {
                    WoodpeckerBetween(model: model, run: run)
                }
            case .report:
                if let report = model.report {
                    WoodpeckerReportView(model: model, report: report)
                }
            }
        }
        .sheet(isPresented: $model.showsPremium, onDismiss: { Task { await model.load() } }) {
            PremiumSheet()
        }
    }
}

// MARK: Entry

private struct WoodpeckerEntry: View {
    let model: WoodpeckerModel
    let overview: WoodpeckerOverview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                switch overview.state {
                case .discovery: discovery
                case .premiumRequired: premium
                case .calibrate: calibrate
                case .create: WoodpeckerCreatePanel(model: model, overview: overview)
                case .run, .unknown:
                    Text("This version of the app cannot show your set. Update ChessDesk to carry on.")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                }
                if let error = model.error { ErrorLine(text: error) }
                rules
                if !overview.history.isEmpty { SavedResults(model: model, history: overview.history) }
            }
            .puzzlesPage()
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Text("Free discovery")
                .cdFont(.small)
                .foregroundStyle(CD.accentStrong)
            Text("Try the same positions twice")
                .cdFont(.pageTitle)
                .foregroundStyle(CD.ink)
            Text(WoodpeckerCopy.method)
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                CheckPoint(text: "\(overview.discovery.size) mixed positions at your puzzle rating.")
                CheckPoint(text: "\(CDFormat.plural(overview.discovery.cycles, "timed cycle")): the second aims to halve your first time.")
                CheckPoint(text: "Free. Your times stay saved.")
            }
            Button(model.isBusy ? "Preparing…" : "Start my free \(overview.discovery.size)-position set") {
                Task { await model.create(size: nil, theme: nil) }
            }
            .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            .disabled(model.isBusy)
            .padding(.top, CD.Space.s4)
            Text("One discovery set per account. Premium adds custom sets and more cycles.")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
        }
    }

    private var premium: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Text("Your free discovery is done or abandoned. Your results are saved below.")
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Make tactics automatic")
                .cdFont(.pageTitle)
                .foregroundStyle(CD.ink)
            Text("Premium builds sets of the size and theme you choose, and keeps the cycles going until the patterns are reflexes. Rated puzzles stay free.")
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("See Premium") { model.showsPremium = true }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .padding(.top, CD.Space.s4)
        }
    }

    private var calibrate: some View {
        let calibration = overview.calibration
        let left = max(0, calibration.required - calibration.attempts)
        return VStack(alignment: .leading, spacing: CD.Space.s12) {
            Text("First, a calibrated puzzle rating")
                .cdFont(.plateTitle)
                .foregroundStyle(CD.ink)
            Text("To build a set at the right difficulty, \(calibration.required) rated puzzles are needed. Solve \(CDFormat.plural(left, "more puzzle")) to unlock your first set.")
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: CD.Space.s12) {
                CDMeter(value: Double(calibration.attempts) / Double(max(1, calibration.required)))
                Text("\(calibration.attempts) / \(calibration.required)")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink)
                    .cdNumber()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(calibration.attempts) of \(calibration.required) rated puzzles")
            NavigationLink { PuzzlesRoute.rated.screen } label: { Text("Solve rated puzzles") }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .padding(.top, CD.Space.s4)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            SectionHeader(title: "The rules of a cycle")
            CheckPoint(text: "The set never changes. Every cycle replays the same puzzles in the same order.")
            CheckPoint(text: "No hints and no skipping: calculate fully, then play your move.")
            CheckPoint(text: "A wrong move counts as wrong for the cycle and you move on.")
            CheckPoint(text: "Beat your previous time. Halving it is the goal.")
        }
    }
}

/// Size and theme of a new set, within the server's rules.
private struct WoodpeckerCreatePanel: View {
    let model: WoodpeckerModel
    let overview: WoodpeckerOverview
    @State private var size: Int
    @State private var theme: String?

    init(model: WoodpeckerModel, overview: WoodpeckerOverview) {
        self.model = model
        self.overview = overview
        _size = State(initialValue: overview.creation.sizes.default)
    }

    private var sizes: WoodpeckerOverview.Creation.Sizes { overview.creation.sizes }

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Build your set")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text("Puzzles are drawn around your puzzle rating. The set never changes once it is built.")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Set size").cdFont(.meta).foregroundStyle(CD.ink3)
                HStack(spacing: CD.Space.s6) {
                    ForEach(sizes.presets, id: \.self) { preset in
                        FilterChip(label: CDFormat.count(preset), selected: size == preset) { size = preset }
                    }
                }
                Stepper(value: $size, in: sizes.min...sizes.max, step: 10) {
                    Text("\(CDFormat.count(size)) puzzles")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                }
                .frame(minHeight: 44)
                Text("\(CDFormat.count(sizes.min)) to \(CDFormat.count(sizes.max)) puzzles.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }

            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Theme").cdFont(.meta).foregroundStyle(CD.ink3)
                Menu {
                    Picker("Theme", selection: Binding(get: { theme ?? "" }, set: { theme = $0.isEmpty ? nil : $0 })) {
                        Text("Mixed (recommended)").tag("")
                        ForEach(overview.creation.themeGroups, id: \.group) { group in
                            Section(group.group) {
                                ForEach(group.themes) { Text($0.label).tag($0.id) }
                            }
                        }
                    }
                } label: {
                    FilterMenuLabel(text: themeLabel)
                }
                .accessibilityLabel("Set theme")
            }

            Button(model.isBusy ? "Building your set…" : "Create my set") {
                Task { await model.create(size: size, theme: theme) }
            }
            .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            .disabled(model.isBusy)
            if overview.completedSets > 0 {
                Text("\(CDFormat.plural(overview.completedSets, "completed set")) so far.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
        }
    }

    private var themeLabel: String {
        guard let theme else { return "Mixed (recommended)" }
        return overview.creation.themeGroups.flatMap(\.themes).first { $0.id == theme }?.label ?? theme
    }
}

// MARK: Solving

private struct WoodpeckerSolving: View {
    let model: WoodpeckerModel
    @State private var confirmsRetire = false
    @State private var confirmsAbandon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                stats
                if model.isMissingPuzzle {
                    missing
                } else {
                    PuzzleBoardView(
                        board: model.board,
                        orientation: model.solver?.solverSide ?? .white,
                        movableSide: model.movableSide,
                        onMove: model.play
                    )
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        if let solver = model.solver, let run = model.run {
                            TurnLine(side: solver.solverSide, meta: "\(CDFormat.count(run.set.remaining)) puzzles, \(run.set.theme?.label ?? "mixed")")
                        }
                        notice
                        if let error = model.error {
                            HStack(spacing: CD.Space.s12) {
                                ErrorLine(text: error)
                                Button("Reload") { Task { await model.load() } }
                                    .buttonStyle(.cd(.secondary, size: .small))
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    .pageGutter()
                }
                if let cycles = model.run?.cycles, !cycles.isEmpty {
                    VStack(alignment: .leading, spacing: CD.Space.s8) {
                        Text("Previous cycles").cdFont(.meta).foregroundStyle(CD.ink3)
                        CycleTable(cycles: cycles)
                    }
                    .pageGutter()
                }
                footer
            }
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Retire this puzzle?", isPresented: $confirmsRetire, titleVisibility: .visible) {
            Button("Retire puzzle", role: .destructive) { Task { await model.retire() } }
        } message: {
            Text("Only for a flawed or broken puzzle. It leaves this cycle and every later one, for good.")
        }
        .confirmationDialog("Abandon this set?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("Abandon set", role: .destructive) { Task { await model.abandon() } }
        } message: {
            Text("Its results stay saved. A free discovery cannot be started again.")
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: CD.Space.s12) {
            if let open = model.run?.openCycle {
                TrainerStat(label: "Cycle \(open.cycleNumber)", value: "\(open.solved) / \(open.total)", detail: "done")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = model.elapsedMs(at: context.date)
                TrainerStat(
                    label: "Time",
                    value: WoodpeckerFormat.time(elapsed),
                    detail: "this cycle",
                    accent: model.targetMs.map { elapsed <= $0 } ?? true
                )
            }
            TrainerStat(
                label: "Target",
                value: model.targetMs.map(WoodpeckerFormat.time) ?? "–",
                detail: model.targetMs != nil ? "half the last target" : "cycle 1 sets it"
            )
        }
        .pageGutter()
    }

    @ViewBuilder private var notice: some View {
        switch model.feedback {
        case .idle: TrainerNotice(tone: .neutral, title: "Calculate the full line, then play.", detail: "No hints in a cycle.")
        case .correct: TrainerNotice(tone: .right, title: "Correct.", detail: "Keep going.")
        case .wrong: TrainerNotice(tone: .wrong, title: "Not the move.", detail: "Marked wrong for this cycle, moving on.")
        case .solved: TrainerNotice(tone: .right, title: "Solved.")
        }
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            TrainerNotice(tone: .caution, title: "This puzzle can no longer be shown.", detail: "Retire it to carry on with the cycle.")
            Button("Retire puzzle") { Task { await model.retire() } }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .disabled(model.isBusy)
        }
        .pageGutter()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            CDHairline()
            HStack(spacing: CD.Space.s16) {
                Button("Retire puzzle") { confirmsRetire = true }
                    .buttonStyle(.cd(.ghost, size: .small))
                    .frame(minHeight: 44)
                    .disabled(model.isBusy || model.puzzle == nil || model.ended)
                Button("Abandon set") { confirmsAbandon = true }
                    .buttonStyle(.cd(.danger, size: .small))
                    .frame(minHeight: 44)
                    .disabled(model.isBusy)
            }
            .padding(.leading, -10)
            Text("Retiring is for flawed puzzles only. The set is meant to stay fixed.")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
        }
        .pageGutter()
    }
}

// MARK: Between cycles

private struct WoodpeckerBetween: View {
    let model: WoodpeckerModel
    let run: WoodpeckerRun
    @State private var confirmsFinish = false
    @State private var confirmsAbandon = false

    var body: some View {
        let next = run.between.nextCycle
        let canStart = next.state == .allowed
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                if let last = run.cycles.last {
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        Text("Cycle \(last.cycleNumber) done")
                            .cdFont(.pageTitle)
                            .foregroundStyle(CD.ink)
                        HStack(alignment: .top, spacing: CD.Space.s24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time").cdFont(.small).foregroundStyle(CD.ink3)
                                Text(WoodpeckerFormat.time(last.durationMs)).cdFont(.metricMedium).foregroundStyle(CD.ink).cdNumber()
                                if let target = last.targetMs {
                                    HStack(spacing: CD.Space.s6) {
                                        Text("Target \(WoodpeckerFormat.time(target))").cdFont(.meta).foregroundStyle(CD.ink3).cdNumber()
                                        Text(last.targetBeaten == true ? "Beaten" : "Over")
                                            .cdFont(.meta)
                                            .foregroundStyle(last.targetBeaten == true ? CD.win : CD.loss)
                                    }
                                } else {
                                    Text("Your baseline for the halving").cdFont(.meta).foregroundStyle(CD.ink3)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accuracy").cdFont(.small).foregroundStyle(CD.ink3)
                                Text("\(Int((last.accuracy * 100).rounded()))%").cdFont(.metricMedium).foregroundStyle(CD.ink).cdNumber()
                                Text("\(last.correct) of \(last.total) right").cdFont(.meta).foregroundStyle(CD.ink3).cdNumber()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                CycleTable(cycles: run.cycles)

                if next.state == .premiumRequired {
                    CDCard(tone: .raised, padding: CD.Space.s20) {
                        VStack(alignment: .leading, spacing: CD.Space.s12) {
                            CDBadge(text: "Premium", tone: .premium)
                            Text("Keep the cycles going")
                                .cdFont(.plateTitle)
                                .foregroundStyle(CD.ink)
                            Text(next.message ?? "Your free cycles are done and your results stay saved. Premium adds the next cycles, and sets of your own.")
                                .cdFont(.body)
                                .foregroundStyle(CD.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("See Premium") { model.showsPremium = true }
                                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        }
                    }
                } else if !canStart, let message = next.message {
                    Text(message)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.error { ErrorLine(text: error) }

                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    if canStart {
                        Button("Start cycle \(next.cycleNumber)") { Task { await model.startNextCycle() } }
                            .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                            .disabled(model.isBusy)
                        if let target = next.targetMs {
                            Text("Target for cycle \(next.cycleNumber): \(WoodpeckerFormat.time(target)).")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                                .cdNumber()
                        }
                    }
                    if run.between.canComplete {
                        Button("Finish the set") { confirmsFinish = true }
                            .buttonStyle(.cd(
                                canStart || next.state == .premiumRequired ? .secondary : .primary,
                                size: .large, fullWidth: true
                            ))
                            .disabled(model.isBusy)
                    } else {
                        Text("Finish at least \(CDFormat.plural(run.between.cyclesToComplete, "cycle")) to complete the set. The method recommends around 7.")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Abandon set") { confirmsAbandon = true }
                        .buttonStyle(.cd(.danger))
                        .disabled(model.isBusy)
                        .padding(.top, CD.Space.s8)
                }
            }
            .puzzlesPage()
        }
        .confirmationDialog("Finish this set?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("Finish the set") { Task { await model.finishSet() } }
        } message: {
            Text("The set is archived with its results, and its report opens.")
        }
        .confirmationDialog("Abandon this set?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("Abandon set", role: .destructive) { Task { await model.abandon() } }
        } message: {
            Text("Its results stay saved. A free discovery cannot be started again.")
        }
    }
}

// MARK: Report

private struct WoodpeckerReportView: View {
    let model: WoodpeckerModel
    let report: WoodpeckerReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text(report.status == "completed" ? "Set complete" : "Your last set")
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                    Text(summary)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let first = report.cycles.first, let last = report.cycles.last, last.cycleNumber != first.cycleNumber {
                    HStack(alignment: .top, spacing: CD.Space.s12) {
                        TrainerStat(label: "Cycle 1", value: WoodpeckerFormat.time(first.durationMs), detail: "\(Int((first.accuracy * 100).rounded()))% right")
                        TrainerStat(label: "Cycle \(last.cycleNumber)", value: WoodpeckerFormat.time(last.durationMs), detail: "\(Int((last.accuracy * 100).rounded()))% right")
                        TrainerStat(label: "Time saved", value: "\(report.timeSavedPercent ?? 0)%", detail: "first cycle to last", accent: true)
                    }
                }
                CycleTable(cycles: report.cycles)
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    SectionHeader(
                        title: "Trouble spots",
                        detail: "Puzzles still wrong, or notably slow, in the late cycles. Worth a second look."
                    )
                    if report.troubleSpots.isEmpty {
                        Text("None. Every late-cycle puzzle was fast and right.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                    } else {
                        ForEach(report.troubleSpots.prefix(12)) { spot in
                            HStack(spacing: CD.Space.s16) {
                                StaticBoardView(fen: spot.fen, orientation: spot.orientation == "black" ? .black : .white)
                                    .frame(width: 88, height: 88)
                                VStack(alignment: .leading, spacing: CD.Space.s4) {
                                    Text(spot.wrong > 0 ? "Wrong \(CDFormat.plural(spot.wrong, "time")) in late cycles" : "Right but slow")
                                        .cdFont(.cardTitle)
                                        .foregroundStyle(CD.ink)
                                    Text("Rated \(CDFormat.count(spot.rating)) · average \(WoodpeckerFormat.time(spot.avgMs))")
                                        .cdFont(.meta)
                                        .foregroundStyle(CD.ink3)
                                        .cdNumber()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if report.troubleSpots.count > 12 {
                            Text("And \(report.troubleSpots.count - 12) more.").cdFont(.meta).foregroundStyle(CD.ink3)
                        }
                    }
                }
                Button("Start a new set") { Task { await model.closeReport() } }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            }
            .puzzlesPage()
        }
    }

    private var summary: String {
        var parts = ["\(CDFormat.count(report.size)) puzzles", report.theme?.label ?? "mixed themes", CDFormat.plural(report.cycles.count, "cycle")]
        if report.retired > 0 { parts.append("\(report.retired) retired") }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: Saved results

private struct SavedResults: View {
    let model: WoodpeckerModel
    let history: [WoodpeckerSavedSet]

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            SectionHeader(title: "Your saved results", detail: "Finished and abandoned sets, newest first.")
            ForEach(history) { set in
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    HStack(spacing: CD.Space.s8) {
                        Text("\(CDFormat.count(set.size)) positions")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                        CDBadge(text: set.status == "completed" ? "Completed" : set.status == "abandoned" ? "Abandoned" : set.status.capitalized)
                    }
                    CycleTable(cycles: set.cycles)
                    if !set.unfinished.isEmpty {
                        Text(set.unfinished.map { "Cycle \($0.cycleNumber) unfinished (\($0.correct)/\($0.total) right)" }.joined(separator: " · "))
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
                .padding(.vertical, CD.Space.s4)
            }
            Button("Read the report of your last set") { Task { await model.openReport() } }
                .buttonStyle(.cd(.ghost))
                .padding(.leading, -10)
                .disabled(model.isBusy)
        }
    }
}

// MARK: Small pieces

private struct CheckPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CD.ink3)
                .accessibilityHidden(true)
            Text(text)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ErrorLine: View {
    let text: String

    var body: some View {
        Text(text)
            .cdFont(.small)
            .foregroundStyle(CD.loss)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }
}
