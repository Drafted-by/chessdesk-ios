import ChessCore
import Foundation
import Observation

/// Find the named square, as many as you can in thirty seconds. The site's
/// coordinate trainer (`apps/web/components/coordinate-trainer.tsx`,
/// `lib/coordinates/squares.ts`): a right tap scores and names a new square,
/// never the same one twice in a row; a wrong tap keeps the target.
@Observable
final class CoordinateTrainer {
    enum Phase: Equatable { case idle, playing, over }

    /// The answer to one tap, shown on the square for a moment.
    struct Flash: Equatable {
        let square: Square
        let right: Bool
    }

    static let roundSeconds = 30
    static let bestKey = "cd.coordinates.best"

    private(set) var phase: Phase = .idle
    private(set) var score = 0
    private(set) var best: Int
    private(set) var secondsLeft = CoordinateTrainer.roundSeconds
    private(set) var target: Square?
    private(set) var flash: Flash?
    var orientation: Side = .white
    var showsCoordinates = true

    @ObservationIgnored private var random: () -> Square
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, random: @escaping () -> Square = { Square(index: Int.random(in: 0..<64)) }) {
        self.defaults = defaults
        self.random = random
        best = defaults.integer(forKey: Self.bestKey)
    }

    func start() {
        score = 0
        secondsLeft = Self.roundSeconds
        flash = nil
        phase = .playing
        target = nextTarget(avoiding: nil)
    }

    /// A tap on `square`. True when it was the target.
    @discardableResult
    func tap(_ square: Square) -> Bool {
        guard phase == .playing, let target else { return false }
        let right = square == target
        flash = Flash(square: square, right: right)
        if right {
            score += 1
            self.target = nextTarget(avoiding: target)
        }
        return right
    }

    /// One second of the round has gone.
    func tick() {
        guard phase == .playing else { return }
        secondsLeft = max(0, secondsLeft - 1)
        if secondsLeft == 0 { finish() }
    }

    func clearFlash() { flash = nil }

    func flip() { orientation = orientation.opposite }

    private func finish() {
        phase = .over
        target = nil
        if score > best {
            best = score
            defaults.set(best, forKey: Self.bestKey)
        }
    }

    private func nextTarget(avoiding previous: Square?) -> Square {
        var square = random()
        while square == previous { square = random() }
        return square
    }
}
