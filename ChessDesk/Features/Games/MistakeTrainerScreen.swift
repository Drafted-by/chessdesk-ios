import ChessCore
import SwiftUI

/// Today's session of the player's own mistakes: the position where the game
/// went wrong, and this time the better move to find. A working screen.
struct MistakeTrainerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Loadable(
            id: AnyHashable(app.accountRevision),
            failureTitle: "Your mistakes did not load",
            load: {
                guard let token = app.token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
                return try await app.api.mistakes(token: token)
            },
            content: { queue in
                if queue.due.isEmpty {
                    LoadFailureView(
                        title: "Nothing to solve today",
                        message: "Your mistakes come back here just before you would repeat them."
                    )
                } else {
                    MistakeSession(mistakes: queue.due, close: { dismiss() })
                }
            }
        )
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
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
    }
}

struct MistakeSession: View {
    let mistakes: [Mistake]
    let close: () -> Void

    @Environment(AppModel.self) private var app
    @State private var index = 0
    @State private var position: Position
    @State private var lastMove: Move?
    @State private var verdict: BoardVerdict?
    @State private var outcome: MistakeResult?
    @State private var isChecking = false
    @State private var solved = 0

    init(mistakes: [Mistake], close: @escaping () -> Void) {
        self.mistakes = mistakes
        self.close = close
        _position = State(initialValue: Position(fen: mistakes[0].fen) ?? .start)
    }

    private var mistake: Mistake { mistakes[index] }
    private var start: Position { Position(fen: mistake.fen) ?? .start }
    private var best: Move? { Move(uci: mistake.bestUci).map { start.normalized($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            Text("Mistake \(index + 1) of \(mistakes.count)")
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .cdNumber()
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            // The board and its question in the middle of what is left.
            Spacer(minLength: 0)

            BoardView(
                position: position,
                orientation: start.turn,
                lastMove: lastMove,
                arrows: outcome != nil && outcome != .solved ? bestArrow : [],
                verdict: verdict,
                movableSide: outcome == nil && !isChecking ? start.turn : nil,
                onMove: play
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text(headline)
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .cdFont(.ledeSmall)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pageGutter()

            Spacer(minLength: 0)

            Group {
                if outcome == nil {
                    Button("Show me the move") { finish(.revealed) }
                        .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                        .disabled(isChecking)
                } else {
                    Button(index + 1 < mistakes.count ? "Next position" : "Done") { advance() }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                }
            }
            .pageGutter()
            .padding(.bottom, CD.Space.s16)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var bestArrow: [BoardArrow] {
        best.map { [BoardArrow(from: $0.from, to: $0.to, brush: .move)] } ?? []
    }

    private var headline: String {
        switch outcome {
        case .solved: "That is the move."
        case .missed: "Not this time: \(mistake.bestSan) was the move."
        case .revealed: "\(mistake.bestSan) was the move."
        case nil: "\(start.turn == .white ? "White" : "Black") to play. Find a better move."
        }
    }

    private var detail: String {
        let against = mistake.opponent.isEmpty ? "" : " against \(mistake.opponent)"
        return "You played \(mistake.moveLabel) \(mistake.playedSan)\(against). It comes back \(outcome == .solved ? "later" : "soon"), until it is yours."
    }

    /// The engine's move is right; so is a move the engine finds as good.
    private func play(_ move: Move) -> Bool {
        guard outcome == nil, !isChecking, let after = start.playing(move) else { return false }
        position = after
        lastMove = move
        if move == best {
            verdict = BoardVerdict(square: move.to, kind: .right)
            finish(.solved)
            return true
        }
        isChecking = true
        Task {
            var asGood = false
            if let judge = app.judge, let best, let expected = start.playing(best) {
                asGood = await judge.accepts(.equal(fenAfterPlayed: after.fen, fenAfterExpected: expected.fen))
            }
            isChecking = false
            verdict = BoardVerdict(square: move.to, kind: asGood ? .right : .wrong)
            finish(asGood ? .solved : .missed)
        }
        return true
    }

    private func finish(_ result: MistakeResult) {
        guard outcome == nil else { return }
        outcome = result
        if result == .solved { solved += 1 }
        if result == .revealed, let best, let after = start.playing(best) {
            position = after
            lastMove = best
        }
        let id = mistake.id
        Task {
            guard let token = app.token else { return }
            _ = try? await app.api.recordMistakeAttempt(id, result: result, token: token)
        }
    }

    private func advance() {
        guard index + 1 < mistakes.count else {
            close()
            return
        }
        index += 1
        position = Position(fen: mistakes[index].fen) ?? .start
        lastMove = nil
        verdict = nil
        outcome = nil
    }
}
