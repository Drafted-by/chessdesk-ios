import ChessCore
import SwiftUI

/// Before the game: who you face, which side you take and, if you wish, the
/// position to start from. The one screen of the feature that is dressed:
/// the opponent is the subject.
struct BotSetupSheet: View {
    let pick: OpponentPick
    let model: PlayModel
    let started: (BotGameModel) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var side = SideChoice.white
    @State private var rating: Double
    @State private var showsStartField = false
    @State private var startText = ""
    @State private var confirmsReplacing = false
    @State private var signIn: SignInView.Mode?
    @State private var showsPremium = false

    init(pick: OpponentPick, model: PlayModel, started: @escaping (BotGameModel) -> Void) {
        self.pick = pick
        self.model = model
        self.started = started
        if case let .custom(custom) = pick {
            _rating = State(initialValue: Double(custom.defaultRating))
        } else {
            _rating = State(initialValue: 0)
        }
    }

    private var bot: PlayBot? {
        if case let .bot(bot) = pick { return bot }
        return nil
    }

    private var custom: CustomOpponent? {
        if case let .custom(custom) = pick { return custom }
        return nil
    }

    private var name: String { bot?.name ?? custom?.name ?? "" }
    private var avatar: String { bot?.avatar ?? custom?.avatar ?? "" }
    private var shownRating: Int { bot?.rating ?? Int(rating) }

    /// What the pasted position parses to; nil while the field is empty.
    private var parsedStart: Result<BotStart, BotStart.ParseError>? {
        startText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : BotStart.parse(startText)
    }

    /// What stands between this player and this bot, as the server lists it.
    private var gate: BotAccess? {
        switch bot?.access ?? .free {
        case .free: nil
        case .account: app.isSignedIn ? nil : .account
        case .premium: app.hasPremium ? nil : .premium
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CD.Space.s24) {
                    opponent
                    if let custom { strength(custom) }
                    if let gate {
                        gateBlock(gate)
                    } else {
                        sides
                        startPosition
                        startButton
                    }
                }
                .padding(.horizontal, CD.Space.s20)
                .padding(.top, CD.Space.s8)
                .padding(.bottom, CD.Space.s32)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CD.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CD.ink2)
                }
            }
            .toolbarBackground(CD.canvas, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .sheet(item: $signIn) { SignInView(mode: $0) }
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
    }

    // MARK: The opponent

    private var opponent: some View {
        VStack(spacing: CD.Space.s12) {
            BotPortrait(avatar: avatar, name: name)
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(CD.accentLine, lineWidth: 1))
                .padding(4)
                .overlay(Circle().strokeBorder(CD.accent.opacity(0.22), lineWidth: 1))
            VStack(spacing: CD.Space.s4) {
                HStack(spacing: CD.Space.s8) {
                    Text(name)
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                    if let flag = CountryFlag.emoji(for: bot?.country) {
                        Text(flag)
                            .font(.system(size: 22))
                            .accessibilityLabel(bot?.country ?? "")
                    }
                }
                Text("\(CDFormat.count(shownRating)) Elo\(bot.map { " · \($0.country)" } ?? "")")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
            }
            OrnamentRule()
                .frame(maxWidth: 220)
            if let tagline = bot?.tagline {
                Text(tagline)
                    .cdFont(.ledeSmall)
                    .foregroundStyle(CD.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func strength(_ custom: CustomOpponent) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            HStack(alignment: .firstTextBaseline) {
                fieldLabel("Opponent strength")
                Spacer()
                Text("\(CDFormat.count(Int(rating))) rating")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink)
                    .cdNumber()
            }
            Slider(
                value: $rating,
                in: Double(custom.minRating)...Double(custom.maxRating),
                step: Double(max(1, custom.step))
            )
            .tint(CD.accent)
            .accessibilityLabel("Bot rating")
            .accessibilityValue("\(Int(rating))")
            HStack {
                Text(CDFormat.count(custom.minRating))
                Spacer()
                Text(CDFormat.count(custom.maxRating))
            }
            .cdFont(.meta)
            .foregroundStyle(CD.ink4)
            .cdNumber()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .cdFont(.small)
            .foregroundStyle(CD.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Side and position

    private var sides: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            fieldLabel("Your color")
            HStack(spacing: CD.Space.s8) {
                ForEach(SideChoice.allCases, id: \.self) { choice in
                    Button {
                        withAnimation(CD.Motion.state) { side = choice }
                    } label: {
                        VStack(spacing: CD.Space.s8) {
                            KingTile(choice: choice)
                            Text(choice.label)
                                .cdFont(.small)
                                .foregroundStyle(side == choice ? CD.ink : CD.ink3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .background(side == choice ? CD.surface2 : CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
                        .hairline(side == choice ? CD.accentLine : CD.line)
                    }
                    .buttonStyle(CDPressStyle())
                    .accessibilityLabel(choice.label)
                    .accessibilityAddTraits(side == choice ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var startPosition: some View {
        if showsStartField {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                fieldLabel("Start from a position")
                TextEditor(text: $startText)
                    .font(CDFont.mono.font)
                    .foregroundStyle(CD.ink)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 84)
                    .padding(CD.Space.s8)
                    .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(startFailure == nil ? CD.lineStrong : CD.loss.opacity(0.7), radius: CD.Radius.md)
                    .accessibilityLabel("A FEN, or a PGN to continue from its last move")
                Text(startFailure ?? startSummary ?? "Paste a FEN, or a PGN to continue from its last move. Leave empty to play from the usual starting position.")
                    .cdFont(.meta)
                    .foregroundStyle(startFailure == nil ? CD.ink3 : CD.loss)
                    .fixedSize(horizontal: false, vertical: true)
                    .cdNumber()
                if !startText.isEmpty {
                    Button("Clear position") {
                        startText = ""
                        showsStartField = false
                    }
                    .buttonStyle(.cd(.ghost, size: .small))
                }
            }
        } else {
            Button("Start from a position (FEN or PGN)") {
                withAnimation(CD.Motion.state) { showsStartField = true }
            }
            .buttonStyle(.cd(.ghost))
        }
    }

    private var startFailure: String? {
        if case let .failure(error) = parsedStart { return error.message }
        return nil
    }

    private var startSummary: String? {
        guard case let .success(start) = parsedStart else { return nil }
        let turn = start.turn == .white ? "White" : "Black"
        return start.moves.isEmpty
            ? "Position loaded. \(turn) to move."
            : "\(CDFormat.plural(start.moves.count, "move")) loaded. \(turn) to move."
    }

    private var startButton: some View {
        VStack(spacing: CD.Space.s8) {
            if let failure = model.startFailure {
                Text(failure)
                    .cdFont(.small)
                    .foregroundStyle(CD.loss)
            }
            Button(model.isStarting ? "Loading opponent…" : "Start game") {
                if model.resumable != nil { confirmsReplacing = true } else { start() }
            }
            .buttonStyle(.cd(.lead, size: .large, fullWidth: true))
            .disabled(model.isStarting || startFailure != nil)
            .confirmationDialog("Start a new game?", isPresented: $confirmsReplacing, titleVisibility: .visible) {
                Button("Start the new game", role: .destructive, action: start)
                Button("Keep my game", role: .cancel) {}
            } message: {
                Text("Your game in progress against \(model.resumable?.setup.botName ?? "the bot") will be given up.")
            }
        }
    }

    private func start() {
        var chosen = BotStart.standard
        if case let .success(parsed) = parsedStart { chosen = parsed }
        let setup = pick.setup(rating: Int(rating), humanSide: side.resolved(), start: chosen)
        Task {
            if let game = await model.start(setup) { started(game) }
        }
    }

    // MARK: The gate

    /// The server lists this bot for accounts or for Premium: the sheet says
    /// so and offers the way in, instead of a game.
    private func gateBlock(_ gate: BotAccess) -> some View {
        VStack(spacing: CD.Space.s12) {
            Text(gate == .premium ? "\(name) is part of Premium." : "A free account is needed to play \(name).")
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .multilineTextAlignment(.center)
            if gate == .premium {
                Button("See Premium") { showsPremium = true }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            } else {
                Button("Create an account") { signIn = .createAccount }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                Button("Sign in") { signIn = .signIn }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
            }
        }
    }
}

/// The side to take, shown with the king of that side on a light square;
/// "Random" is a king split down the middle.
private struct KingTile: View {
    let choice: SideChoice

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous)
                .fill(CD.Board.light)
            switch choice {
            case .white: king(.white)
            case .black: king(.black)
            case .random:
                king(.white).mask(alignment: .leading) { Rectangle().frame(width: 22) }
                king(.black).mask(alignment: .trailing) { Rectangle().frame(width: 22) }
            }
        }
        .frame(width: 56, height: 56)
        .overlay(RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous).strokeBorder(CD.accentLine, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func king(_ side: Side) -> some View {
        Image(Piece(side, .king).assetName)
            .resizable()
            .frame(width: 44, height: 44)
    }
}
