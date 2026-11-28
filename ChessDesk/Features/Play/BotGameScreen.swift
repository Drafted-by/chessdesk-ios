import ChessCore
import SwiftUI

/// The game: a board, who is to move, the moves, and what to do when it is
/// over. A working screen, no ornament.
struct BotGameScreen: View {
    let model: BotGameModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsResigning = false
    @State private var playsOtherSideNext = false
    @State private var review: String?
    @State private var signIn: SignInView.Mode?

    private var game: BotGame { model.game }
    private var setup: BotGameSetup { game.setup }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    VStack(spacing: CD.Space.s6) {
                        opponentBar
                        BoardView(
                            position: game.position,
                            orientation: game.humanSide,
                            lastMove: game.lastMove,
                            movableSide: game.isOver ? nil : game.humanSide,
                            onMove: { model.play($0) }
                        )
                        .frame(maxWidth: 560)
                        playerBar
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)

                    if let outcome = game.outcome {
                        ResultPanel(
                            model: model,
                            outcome: outcome,
                            playsOtherSideNext: $playsOtherSideNext,
                            review: { review = $0 },
                            signIn: { signIn = $0 },
                            newGame: { dismiss() }
                        )
                        .id("result")
                        .transition(.opacity)
                    }

                    PlayMoveStrip(moves: game.moves, outcome: game.outcome)

                    if !game.isOver {
                        HStack {
                            Button("Resign") { confirmsResigning = true }
                                .buttonStyle(.cd(.ghost))
                            Spacer()
                        }
                    }
                    #if DEBUG
                        Text("Engine: \(model.engineKind.rawValue)")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink4)
                    #endif
                }
                .pageGutter()
                .padding(.top, CD.Space.s8)
                .padding(.bottom, CD.Space.s32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: game.isOver) { _, over in
                guard over else { return }
                withAnimation(CD.Motion.enter) { proxy.scrollTo("result", anchor: .bottom) }
            }
        }
        .navigationTitle(setup.botName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: model.pgn) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(CD.ink2)
                }
                .disabled(game.moves.isEmpty)
                .accessibilityLabel("Share the game as PGN")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .onAppear {
            model.onMovePlayed = { BoardSounds.shared.play(capture: $0) }
            model.begin()
            #if DEBUG
                PlayDebug.autopilot(model)
            #endif
        }
        .onDisappear { model.pause() }
        .onChange(of: app.accountRevision) { _, _ in model.accountChanged() }
        .confirmationDialog("Resign this game?", isPresented: $confirmsResigning, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { model.resign() }
            Button("Keep playing", role: .cancel) {}
        }
        .sheet(item: $signIn) { SignInView(mode: $0) }
        .navigationDestination(item: $review) { GameScreen(id: $0) }
    }

    // MARK: The two players

    private var material: MaterialDiff { MaterialDiff(position: game.position) }

    private var opponentBar: some View {
        HStack(spacing: CD.Space.s8) {
            BotPortrait(avatar: setup.avatar, name: setup.botName)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(CD.lineStrong, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s6) {
                    Text(setup.botName)
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    Text(CDFormat.count(setup.rating))
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
                Text(status)
                    .cdFont(.meta)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: CD.Space.s8)
            CapturedRow(material: material[game.botSide], capturedSide: game.humanSide)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var playerBar: some View {
        HStack(spacing: CD.Space.s8) {
            SideSwatch(side: game.humanSide, size: 11)
                .frame(width: 40)
            Text("You")
                .cdFont(.cardTitle)
                .foregroundStyle(CD.ink)
            Spacer(minLength: CD.Space.s8)
            CapturedRow(material: material[game.humanSide], capturedSide: game.botSide)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    /// Once the game is over the line speaks for the bot ("Checkmated"), in
    /// neutral ink: the result panel carries the player's result.
    private var status: String {
        if let outcome = game.outcome { return outcome.botStatusLine }
        if game.thinking { return "Thinking…" }
        return game.position.isCheck ? "Your move · check" : "Your move"
    }

    private var statusColor: Color {
        if game.isOver { return CD.ink3 }
        return game.thinking ? CD.accent : CD.ink2
    }
}

extension BotGame {
    var thinking: Bool { botToMove }
}

/// The pieces a side has taken, pawn to queen, and "+N" when it is ahead.
private struct CapturedRow: View {
    let material: MaterialDiff.SideMaterial
    /// The side whose pieces were taken.
    let capturedSide: Side

    private static let names: [PieceKind: String] = [.pawn: "pawn", .knight: "knight", .bishop: "bishop", .rook: "rook", .queen: "queen"]

    var body: some View {
        HStack(spacing: CD.Space.s4) {
            ForEach(material.captured, id: \.kind) { group in
                HStack(spacing: -9) {
                    ForEach(0..<group.count, id: \.self) { _ in
                        Image(Piece(capturedSide, group.kind).assetName)
                            .resizable()
                            .frame(width: 18, height: 18)
                            // Black pieces on the dark page need an edge of light.
                            .shadow(color: capturedSide == .black ? CD.ink.opacity(0.75) : .clear, radius: 0.6)
                    }
                }
            }
            if material.advantage > 0 {
                Text("+\(material.advantage)")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
            }
        }
        .frame(minHeight: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        var parts = material.captured.map { group in
            CDFormat.plural(group.count, Self.names[group.kind] ?? "piece")
        }
        if material.advantage > 0 { parts.append("up \(material.advantage)") }
        return parts.isEmpty ? "" : "Captured \(parts.joined(separator: ", "))"
    }
}

/// The moves in one row that follows the game; a finished game ends with
/// its score, as printed in a book.
private struct PlayMoveStrip: View {
    let moves: [PlayedMove]
    let outcome: BotGameOutcome?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CD.Space.s4) {
                    if moves.isEmpty, outcome == nil {
                        Text("Moves will appear here.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .padding(.horizontal, CD.Space.s8)
                    }
                    ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                        HStack(spacing: CD.Space.s4) {
                            if move.side == .white {
                                Text("\(move.moveNumber).").foregroundStyle(CD.ink4)
                            } else if index == 0 {
                                Text("\(move.moveNumber)...").foregroundStyle(CD.ink4)
                            }
                            Text(move.san)
                                .foregroundStyle(index == moves.count - 1 ? CD.ink : CD.ink2)
                        }
                        .cdFont(.san)
                        .cdNumber()
                        .padding(.horizontal, CD.Space.s6)
                        .frame(minHeight: 32)
                        .background(
                            index == moves.count - 1 && outcome == nil ? CD.surface3 : .clear,
                            in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                        )
                        .id(index)
                    }
                    if let outcome {
                        Text("\(BotGameOutcome.printedScore(outcome.result))  \(outcome.scoreSheetEnding)")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                            .padding(.horizontal, CD.Space.s8)
                            .id("end")
                    }
                }
                .padding(.horizontal, CD.Space.s8)
            }
            .frame(minHeight: 44)
            .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
            .hairline()
            .onChange(of: moves.count, initial: true) { _, count in
                guard count > 0 else { return }
                withAnimation(CD.Motion.state) { proxy.scrollTo(count - 1, anchor: .trailing) }
            }
            .onChange(of: outcome) { _, new in
                if new != nil { withAnimation(CD.Motion.state) { proxy.scrollTo("end", anchor: .trailing) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moves.isEmpty ? "No moves yet" : "Moves: \(moves.map(\.san).joined(separator: " "))")
    }
}

/// The game is over: what happened, whether it is kept, and what next.
private struct ResultPanel: View {
    let model: BotGameModel
    let outcome: BotGameOutcome
    @Binding var playsOtherSideNext: Bool
    let review: (String) -> Void
    let signIn: (SignInView.Mode) -> Void
    let newGame: () -> Void

    private var game: BotGame { model.game }
    private var otherSide: String { outcome.humanSide == .white ? "Black" : "White" }

    private var tone: Color {
        switch outcome.tone {
        case .win: CD.win
        case .loss: CD.loss
        case .draw: CD.draw
        }
    }

    var body: some View {
        CDCard(tone: .raised) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text(outcome.title(botName: game.setup.botName))
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: CD.Space.s6) {
                        Text(BotGameOutcome.printedScore(outcome.result))
                            .cdFont(.bodyStrong)
                            .foregroundStyle(tone)
                        Text(method)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                    }
                    .cdNumber()
                }

                kept

                HStack(spacing: CD.Space.s8) {
                    Button(playsOtherSideNext ? "Rematch as \(otherSide)" : "Rematch") {
                        model.rematch(swappingSides: playsOtherSideNext)
                        playsOtherSideNext = false
                    }
                    .buttonStyle(.cd(hasReview ? .secondary : .primary, fullWidth: true))
                    Button("New game", action: newGame)
                        .buttonStyle(.cd(.secondary, fullWidth: true))
                }
                Toggle(isOn: $playsOtherSideNext) {
                    HStack(spacing: CD.Space.s8) {
                        SideSwatch(side: outcome.humanSide.opposite)
                        Text("Play \(otherSide) next")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                    }
                }
                .tint(CD.accent)
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var method: String {
        let last = game.moves.last.map { BotGameOutcome.moveNumber(ofPly: $0.ply) }
        return "\(outcome.terminationPhrase(lastMoveNumber: last)) · against \(game.setup.botName) \(CDFormat.count(game.setup.rating))"
    }

    /// Review leads when the game is in the account.
    private var hasReview: Bool {
        switch model.saving {
        case .saved, .saving, .waitingForAccount: true
        case .idle, .failed, .unavailable: false
        }
    }

    /// What became of the game: saved, saving, waiting for an account.
    @ViewBuilder private var kept: some View {
        switch model.saving {
        case let .saved(gameID):
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text("Saved to your games. Review it to see your accuracy and the moves that decided the game.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review this game") { review(gameID) }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            }
        case .saving:
            HStack(spacing: CD.Space.s8) {
                ProgressView().tint(CD.ink3)
                Text("Saving to your games…")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            }
            .frame(minHeight: 44)
        case .waitingForAccount:
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text("Save it to a free ChessDesk account: the full review, the moves that decided it, and your mistakes back as drills.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create an account to save it") { signIn(.createAccount) }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                Button("Sign in") { signIn(.signIn) }
                    .buttonStyle(.cd(.ghost))
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text("The game was not saved: \(message)")
                    .cdFont(.small)
                    .foregroundStyle(CD.loss)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.save() }
                    .buttonStyle(.cd(.secondary))
            }
        case .idle, .unavailable:
            EmptyView()
        }
    }
}
