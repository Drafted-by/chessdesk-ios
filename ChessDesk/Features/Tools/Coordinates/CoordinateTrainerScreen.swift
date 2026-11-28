import ChessCore
import SwiftUI
import UIKit

/// Tap the named square: thirty seconds a round, on the player's own board.
struct CoordinateTrainerScreen: View {
    @State private var trainer = CoordinateTrainer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: CD.Space.s16) {
                status
                prompt
                board
                    .frame(maxWidth: 560)
                controls
                if trainer.phase == .over {
                    Text("You found \(CDFormat.plural(trainer.score, "square")) in \(CoordinateTrainer.roundSeconds) seconds.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .multilineTextAlignment(.center)
                        .cdNumber()
                }
            }
            .pageGutter()
            .padding(.vertical, CD.Space.s16)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Coordinates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .task(id: trainer.phase) {
            guard trainer.phase == .playing else { return }
            while !Task.isCancelled, trainer.phase == .playing {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                trainer.tick()
            }
        }
        #if DEBUG
            // `-CDCoordinatesStart YES`: a round under way, with a wrong tap shown.
            .onAppear {
                guard UserDefaults.standard.bool(forKey: "CDCoordinatesStart"), trainer.phase == .idle else { return }
                trainer.start()
                if let target = trainer.target, let other = Square(file: (target.file + 3) % 8, rank: target.rank) {
                    trainer.tap(other)
                }
            }
        #endif
        .task(id: trainer.flash) {
            guard trainer.flash != nil else { return }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            trainer.clearFlash()
        }
    }

    private var status: some View {
        HStack {
            HStack(spacing: CD.Space.s12) {
                label("Score", trainer.score)
                if trainer.best > 0 { label("Best", trainer.best) }
            }
            Spacer()
            Text("\(trainer.phase == .playing ? trainer.secondsLeft : CoordinateTrainer.roundSeconds)s")
                .cdFont(.bodyStrong)
                .foregroundStyle(trainer.phase == .playing && trainer.secondsLeft <= 5 ? CD.loss : CD.ink3)
                .cdNumber()
                .accessibilityLabel("\(trainer.secondsLeft) seconds left")
        }
    }

    private func label(_ title: String, _ value: Int) -> some View {
        HStack(spacing: CD.Space.s4) {
            Text(title).foregroundStyle(CD.ink3)
            Text("\(value)").foregroundStyle(CD.ink)
        }
        .cdFont(.bodyStrong)
        .cdNumber()
        .accessibilityElement(children: .combine)
    }

    private var prompt: some View {
        Group {
            switch trainer.phase {
            case .idle: Text("Tap Start, then the square named here.").cdFont(.lede)
            case .over: Text("Time!").cdFont(.pageTitle)
            case .playing: Text(trainer.target?.description ?? "").font(.custom("Geist-Bold", size: 48, relativeTo: .largeTitle))
            }
        }
        .foregroundStyle(trainer.phase == .playing ? CD.ink : CD.ink2)
        .cdNumber()
        .frame(minHeight: 60)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var board: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = BoardGeometry(side: side, orientation: trainer.orientation)
            ZStack(alignment: .topLeading) {
                BoardSquaresLayer(orientation: trainer.orientation, showsCoordinates: trainer.showsCoordinates)
                if let flash = trainer.flash {
                    let rect = geometry.rect(of: flash.square)
                    Rectangle()
                        .fill(flash.right ? CD.win : CD.loss)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
            .opacity(trainer.phase == .playing ? 1 : 0.85)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let square = geometry.square(at: location) else { return }
                let right = trainer.tap(square)
                UIImpactFeedbackGenerator(style: right ? .light : .rigid).impactOccurred()
            }
            .animation(reduceMotion ? nil : CD.Motion.press, value: trainer.flash)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(trainer.phase == .playing ? "Board. Find \(trainer.target?.description ?? "")." : "Board")
    }

    private var controls: some View {
        VStack(spacing: CD.Space.s12) {
            if trainer.phase != .playing {
                Button(trainer.phase == .idle ? "Start" : "Play again") { trainer.start() }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            }
            HStack(spacing: CD.Space.s8) {
                Button(trainer.orientation == .white ? "White view" : "Black view", systemImage: "arrow.up.arrow.down") {
                    trainer.flip()
                }
                .buttonStyle(.cd(.secondary, fullWidth: true))
                Button(trainer.showsCoordinates ? "Coordinates on" : "Coordinates off") {
                    trainer.showsCoordinates.toggle()
                }
                .buttonStyle(.cd(.secondary, fullWidth: true))
            }
        }
    }
}

#Preview {
    NavigationStack { CoordinateTrainerScreen() }
}
