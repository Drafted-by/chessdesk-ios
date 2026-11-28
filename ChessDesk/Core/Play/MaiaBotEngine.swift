import ChessCore
import Foundation

/// Maia-3 (5M), the network the site runs in the browser, run on the phone:
/// encode the position and the rating, run the network, draw a legal move
/// from its policy. A port of the site's `lib/play/engine/maia-engine.ts`.
///
/// As on the site, the opponent's rating is set to the bot's own (a
/// symmetric game) and no move history is sent.
nonisolated struct MaiaBotEngine: BotEngine {
    /// Sample from the move distribution, so a player does not meet the same
    /// game twice; the nucleus filter trims the rare low-probability blunder.
    static let samplingTemperature = 1.0
    static let samplingTopP = 0.9

    let kind = BotEngineKind.maia
    let session: OnnxSession

    init(model: Data) throws {
        session = try OnnxSession(data: model)
        guard session.outputs.contains(MaiaEncoding.policyName) else {
            throw BotEngineError.unavailable("the network has no \(MaiaEncoding.policyName) output")
        }
    }

    func bestMove(fen: String, rating: Int, temperature: Double?) async throws -> String {
        try await choose(fen: fen, rating: rating, temperature: temperature)
    }

    /// Off the caller's actor: a move is some ten milliseconds of arithmetic.
    @concurrent
    private func choose(fen: String, rating: Int, temperature: Double?) async throws -> String {
        guard let position = Position(fen: fen) else { throw BotEngineError.noMove }
        let policy = try policy(for: position, rating: rating)
        guard let move = MaiaEncoding.decode(
            policy: policy,
            position: position,
            temperature: temperature ?? Self.samplingTemperature,
            topP: Self.samplingTopP
        ) else { throw BotEngineError.noMove }
        return move.uci
    }

    /// The raw policy, one value per entry of the move vocabulary.
    func policy(for position: Position, rating: Int) throws -> [Float] {
        let inputs = MaiaEncoding.inputs(for: position, selfElo: Double(rating), opponentElo: Double(rating))
        guard let policy = try session.run(inputs)[MaiaEncoding.policyName], policy.count == MaiaEncoding.policySize else {
            throw BotEngineError.unavailable("the network did not answer with a policy")
        }
        return policy.floats
    }
}

/// The Maia network on this device: fetched once from where the site serves
/// it, then read from disk. The weights are AGPL-3.0 and are neither in the
/// app nor in its repository.
actor MaiaModelStore {
    static let shared = MaiaModelStore()

    private let folder: URL
    private let session: URLSession
    private var downloads: [URL: Task<Data, Error>] = [:]
    private var engines: [URL: MaiaBotEngine] = [:]

    init(
        folder: URL = URL.applicationSupportDirectory.appending(path: "ChessDesk/Engines", directoryHint: .isDirectory),
        session: URLSession = .shared
    ) {
        self.folder = folder
        self.session = session
    }

    nonisolated func file(for model: MaiaModelInfo) -> URL {
        folder.appending(path: "\(model.model).onnx")
    }

    /// The engine for `model`, loaded once per launch. The download goes on
    /// when the caller stops waiting, so the next game finds the file.
    func engine(for model: MaiaModelInfo) async throws -> MaiaBotEngine {
        if let ready = engines[model.url] { return ready }
        let data = try await data(for: model)
        do {
            let engine = try await Self.load(data)
            engines[model.url] = engine
            return engine
        } catch {
            // A file the app cannot run is not kept: the next game fetches it again.
            try? FileManager.default.removeItem(at: file(for: model))
            throw error
        }
    }

    @concurrent
    private static func load(_ data: Data) async throws -> MaiaBotEngine {
        try MaiaBotEngine(model: data)
    }

    private func data(for model: MaiaModelInfo) async throws -> Data {
        let file = file(for: model)
        if let stored = try? Data(contentsOf: file, options: .mappedIfSafe), !stored.isEmpty { return stored }
        if let running = downloads[model.url] { return try await running.value }
        let session = session
        let folder = folder
        let task = Task<Data, Error> {
            var request = URLRequest(url: model.url)
            request.timeoutInterval = 120
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                throw BotEngineError.unavailable("the network could not be downloaded")
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            // A file that can be fetched again does not belong in a backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var target = file
            try? target.setResourceValues(values)
            return data
        }
        downloads[model.url] = task
        defer { downloads[model.url] = nil }
        return try await task.value
    }
}
