import AVFoundation
import Observation
import UIKit

/// Move and capture sounds, the same two files as the site, with a light
/// haptic. Sounds respect the silent switch (ambient session). The files are
/// not in the repository (`scripts/fetch-sounds.sh`); without them the board
/// is silent and only the haptic plays.
final class BoardSounds {
    static let shared = BoardSounds()

    private var players: [String: AVAudioPlayer] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private init() {
        for name in ["move", "capture"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.volume = 0.6
            player.prepareToPlay()
            players[name] = player
        }
    }

    func play(capture: Bool) {
        let player = players[capture ? "capture" : "move"]
        player?.currentTime = 0
        player?.play()
        haptic.impactOccurred(intensity: capture ? 0.9 : 0.6)
    }
}

/// The site's narration key: FNV-1a (32 bit) over the UTF-16 units of the
/// text, as 8 hex digits. It must match `narrationKey` in
/// `apps/web/lib/training/narration.ts`, or no clip is ever found.
nonisolated enum NarrationKey {
    static func make(_ text: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for unit in text.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }

    static func clipURL(for text: String, in narration: Narration?) -> URL? {
        guard let narration, !text.isEmpty else { return nil }
        let key = make(text)
        guard narration.keys.contains(key) else { return nil }
        return URL(string: "\(narration.base)/\(key).mp3")
    }
}

/// Reads a move's note aloud when the course is voiced. One clip at a time;
/// a new note stops the previous one.
@Observable
final class NarrationPlayer {
    private static let enabledKey = "cd.narration.enabled"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { stop() }
        }
    }

    private var player: AVPlayer?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func speak(_ comments: [String], narration: Narration?) {
        stop()
        guard isEnabled else { return }
        let urls = comments.compactMap { NarrationKey.clipURL(for: $0, in: narration) }
        guard !urls.isEmpty else { return }
        // Spoken notes should be heard even with the ringer off, like a podcast.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let queue = AVQueuePlayer(items: urls.map { AVPlayerItem(url: $0) })
        queue.play()
        player = queue
    }

    func stop() {
        player?.pause()
        player = nil
    }
}
