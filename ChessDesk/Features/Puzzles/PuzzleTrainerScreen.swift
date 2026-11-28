import ChessCore
import SwiftUI

/// Puzzles one after the other: the free set for everyone, rated puzzles
/// for a player with an account. A working screen: the board first.
struct PuzzleTrainerScreen: View {
    let source: PuzzleTrainerModel.Source

    @Environment(AppModel.self) private var app
    @State private var model: PuzzleTrainerModel?
    @State private var signIn: SignInView.Mode?

    var body: some View {
        Group {
            if source == .rated, !app.isSignedIn {
                ScrollView { AccountPitch(signIn: $signIn).puzzlesPage() }
            } else if let model {
                PuzzleTrainerContent(model: model, signIn: $signIn)
            } else {
                LoadingView()
            }
        }
        .navigationTitle(source == .free ? "Free puzzles" : "Rated puzzles")
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
        .sheet(item: $signIn) { SignInView(mode: $0) }
        .task(id: app.accountRevision) {
            guard source == .free || app.isSignedIn else {
                model = nil
                return
            }
            let fresh = PuzzleTrainerModel(source: source, api: app.api, token: { [app] in app.token })
            model = fresh
            await fresh.start()
        }
    }
}

private struct PuzzleTrainerContent: View {
    let model: PuzzleTrainerModel
    @Binding var signIn: SignInView.Mode?
    @Environment(AppModel.self) private var app

    var body: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .failed(message):
            LoadFailureView(title: "No puzzle right now", message: message) {
                Task { await model.start() }
            }
        case .empty, .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    filters
                    stats
                    if model.phase == .empty {
                        TrainerNotice(tone: .neutral, title: "No puzzles match this filter.", detail: "Try another theme or difficulty.")
                    } else {
                        trainer
                    }
                    footer
                }
                .padding(.top, CD.Space.s8)
                .padding(.bottom, CD.Space.s40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Filters

    @ViewBuilder private var filters: some View {
        if model.source == .free {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CD.Space.s6) {
                        FilterChip(label: "All themes", selected: model.theme == nil) {
                            Task { await model.setFilters(theme: nil, band: model.band) }
                        }
                        ForEach(model.freeThemes) { theme in
                            FilterChip(label: theme.label, selected: model.theme == theme.id) {
                                Task { await model.setFilters(theme: theme.id, band: model.band) }
                            }
                        }
                    }
                    .pageGutter()
                }
                Menu {
                    Picker("Difficulty", selection: Binding(
                        get: { model.band ?? "" },
                        set: { value in Task { await model.setFilters(theme: model.theme, band: value.isEmpty ? nil : value) } }
                    )) {
                        Text("Any difficulty").tag("")
                        ForEach(model.bands) { band in Text(band.label).tag(band.id) }
                    }
                } label: {
                    FilterMenuLabel(text: model.bands.first { $0.id == model.band }?.label ?? "Any difficulty")
                }
                .accessibilityLabel("Difficulty")
                .pageGutter()
            }
        } else if !model.themeGroups.isEmpty {
            Menu {
                Picker("Theme", selection: Binding(
                    get: { model.theme ?? "" },
                    set: { value in Task { await model.setRatedTheme(value.isEmpty ? nil : value) } }
                )) {
                    Text("All themes").tag("")
                    ForEach(model.themeGroups, id: \.group) { group in
                        Section(group.group) {
                            ForEach(group.themes) { theme in Text(theme.label).tag(theme.id) }
                        }
                    }
                }
            } label: {
                FilterMenuLabel(text: themeName)
            }
            .accessibilityLabel("Theme")
            .pageGutter()
        }
    }

    private var themeName: String {
        guard let id = model.theme else { return "All themes" }
        return model.themeGroups.flatMap(\.themes).first { $0.id == id }?.label ?? id
    }

    // MARK: Numbers

    private var stats: some View {
        HStack(alignment: .top, spacing: CD.Space.s12) {
            if model.source == .rated {
                TrainerStat(
                    label: "Puzzle rating",
                    value: model.rating.map(CDFormat.count) ?? "–",
                    detail: model.lastDelta != nil ? "last puzzle" : "live",
                    accent: true,
                    delta: model.lastDelta
                )
                TrainerStat(label: "Streak", value: "\(model.streak)", detail: "clean solves")
                TrainerStat(label: "Best streak", value: "\(model.bestStreak)", detail: "this session")
            } else {
                TrainerStat(
                    label: "Puzzle",
                    value: model.puzzles.isEmpty ? "0" : "\(model.index + 1) of \(model.puzzles.count)",
                    detail: model.solvedInSet > 0 ? "\(model.solvedInSet) solved" : "in this set"
                )
                TrainerStat(label: "Streak", value: "\(model.streak)", detail: "clean solves", accent: true)
                TrainerStat(label: "Best streak", value: "\(model.bestStreak)", detail: "on this phone")
            }
        }
        .pageGutter()
    }

    // MARK: Board

    @ViewBuilder private var trainer: some View {
        let side = model.solver?.solverSide ?? .white
        PuzzleBoardView(
            board: model.board,
            orientation: side,
            hint: model.hintSquare,
            movableSide: model.movableSide,
            onMove: model.play
        )

        VStack(alignment: .leading, spacing: CD.Space.s12) {
            if let puzzle = model.puzzle {
                TurnLine(side: side, meta: "Puzzle rated \(CDFormat.count(puzzle.rating))")
            }
            notice(side: side)
            if model.hintUsed, let themes = model.puzzle?.themes, !themes.isEmpty {
                FlowThemes(themes: themes)
            }
            if let error = model.submitError {
                HStack(spacing: CD.Space.s12) {
                    Text(error)
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await model.retrySubmit() } }
                        .buttonStyle(.cd(.secondary, size: .small))
                        .frame(minHeight: 44)
                }
            }
            if let notice = model.notice {
                Text(notice)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .pageGutter()
    }

    @ViewBuilder private func notice(side: Side) -> some View {
        let name = side == .white ? "White" : "Black"
        switch model.feedback {
        case .idle:
            TrainerNotice(tone: .neutral, title: "Find the best move for \(name).")
        case .correct:
            TrainerNotice(tone: .right, title: "Correct.", detail: "Keep going.")
        case .wrong:
            TrainerNotice(tone: .wrong, title: "Not the move.", detail: "Try again.")
        case .solved:
            TrainerNotice(tone: .right, title: "Solved.", detail: "Clean, with no hint.")
        case .completed:
            TrainerNotice(
                tone: .caution, title: "Line completed.",
                detail: model.source == .rated
                    ? "It counts as failed: a wrong move or a hint was used."
                    : "Not a clean solve: a wrong move or a hint was used."
            )
        case .revealed:
            TrainerNotice(
                tone: .caution, title: "The solution.",
                detail: model.source == .rated ? "Seeing it counts as failed." : "Seeing it is not a clean solve."
            )
        }
    }

    @ViewBuilder private var actions: some View {
        if model.isLineOver {
            Button("Next puzzle") { Task { await model.next() } }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .disabled(model.isBusy)
        } else {
            HStack(spacing: CD.Space.s8) {
                Button {
                    model.hint()
                } label: {
                    Label("Hint", systemImage: "eye").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.cd(.secondary, fullWidth: true))
                .disabled(model.movableSide == nil || model.showsHint)
                Button("Solution") { Task { await model.showSolution() } }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
                    .disabled(model.movableSide == nil)
                Button("Skip") { Task { await model.next() } }
                    .buttonStyle(.cd(.ghost, fullWidth: true))
                    .disabled(model.isBusy || model.puzzle == nil)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            CDHairline()
            if model.source == .rated {
                Text("A clean solve raises your rating. A hint, a wrong move, the solution or a skip lowers it.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Progress is kept on this phone.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                if !app.isSignedIn {
                    Text("An account adds a puzzle rating, puzzles served at your level from the whole library, and the Woodpecker Method.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Create an account") { signIn = .createAccount }
                        .buttonStyle(.cd(.ghost))
                        .padding(.leading, -10)
                }
            }
        }
        .pageGutter()
        .padding(.top, CD.Space.s8)
    }
}

/// The themes of a puzzle, once a hint has given the motif away.
private struct FlowThemes: View {
    let themes: [PuzzleTheme]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CD.Space.s6) {
                ForEach(themes) { CDBadge(text: $0.label) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Themes: \(themes.map(\.label).joined(separator: ", "))")
    }
}

/// What an account adds to puzzles, with the two ways in.
struct AccountPitch: View {
    @Binding var signIn: SignInView.Mode?
    /// False when the screen's primary action is elsewhere.
    var leads = true

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Your rating, your level")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    point("A puzzle rating that moves with every puzzle.")
                    point("Puzzles served just above your level, from the whole library.")
                    point("The Woodpecker Method: one set, solved faster each cycle.")
                }
                Button("Create an account") { signIn = .createAccount }
                    .buttonStyle(.cd(leads ? .primary : .secondary, size: .large, fullWidth: true))
                    .padding(.top, CD.Space.s4)
                Button("Sign in") { signIn = .signIn }
                    .buttonStyle(.cd(leads ? .secondary : .ghost, size: .large, fullWidth: true))
            }
        }
    }

    private func point(_ text: String) -> some View {
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
