import ChessCore
import Foundation
import Observation

/// Which numbers the builder shows beside the moves of a position.
nonisolated enum StatsSource: String, Hashable, Sendable, CaseIterable {
    /// Lichess players of one rating band: the closest to real opponents.
    case players
    case masters
    /// The player's own games with the repertoire's colour.
    case mine

    var label: String {
        switch self {
        case .players: "Players"
        case .masters: "Masters"
        case .mine: "My games"
        }
    }
}

/// One move that can be played from the current position of the builder:
/// a move of the repertoire, or one that is commonly played there.
nonisolated struct BuilderMove: Hashable, Identifiable, Sendable {
    struct Stat: Hashable, Sendable {
        let games: Int
        /// Share of the games of the position, 0…1.
        let frequency: Double
        /// The three parts of the result bar. By colour (White wins, draws,
        /// Black wins) for a reference database; from the player's side
        /// (wins, draws, losses) for their own games.
        let first: Int
        let draws: Int
        let last: Int
        let isMine: Bool
        let opening: String?
    }

    let san: String
    /// Nil when the server could not name the move: it is shown, not played.
    let uci: String?
    let inRepertoire: Bool
    /// A frequent reply of the opponent the repertoire does not answer yet.
    let isUnanswered: Bool
    let glyph: String
    let hasNote: Bool
    /// Moves of the repertoire below this one.
    let movesBelow: Int
    let stat: Stat?

    var id: String { uci ?? san }
}

/// The repertoire builder: where the player stands in the tree, what can be
/// played from there, and the changes sent to the server. The server owns the
/// tree: every write answers with the repertoire as it now stands, and a
/// refused write is followed by a fresh read.
@Observable
final class RepertoireBuilderModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum StatsPhase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Notice: Equatable {
        let text: String
        var isError = false
    }

    /// A move played on the board that the server has not answered for yet.
    struct Pending: Equatable {
        let path: [String]
        let position: Position
        let move: Move
        let san: String
    }

    let id: String
    private(set) var phase: Phase = .loading
    private(set) var detail: RepertoireDetail?
    /// Where the player stands: the moves from the start, in UCI.
    private(set) var path: [String] = []
    private(set) var pending: Pending?
    private(set) var stats: RepertoirePosition?
    private(set) var statsPhase: StatsPhase = .loading
    private(set) var isWriting = false
    /// The rating bands the server offers, kept while a position loads.
    private(set) var ratingBands: [RepertoirePosition.RatingBand] = []
    /// The band asked for; nil until the player chooses one (the server has a default).
    private(set) var ratings: String?
    var source: StatsSource = .players
    var notice: Notice?
    var showsPremium = false
    var flipped = false

    private let api: any RepertoiresAPI & Sendable
    private let token: String
    private let debounce: Duration
    private let onUnauthorized: () -> Void
    private var statsTask: Task<Void, Never>?
    private var cache: [StatsKey: RepertoirePosition] = [:]

    private struct StatsKey: Hashable {
        let path: [String]
        let ratings: String?
    }

    /// - Parameter debounce: how long the player must stay on a position
    ///   before its statistics are asked for. The server allows 60 positions
    ///   a minute; walking a line quickly must not spend them.
    init(
        id: String,
        api: any RepertoiresAPI & Sendable,
        token: String,
        debounce: Duration = .milliseconds(350),
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.id = id
        self.api = api
        self.token = token
        self.debounce = debounce
        self.onUnauthorized = onUnauthorized
    }

    // MARK: Reading the state

    var tree: [RepertoireNode] { detail?.tree ?? [] }
    var side: Side { detail?.side ?? .white }
    var orientation: Side { flipped ? side.opposite : side }
    var isEditable: Bool { detail?.editable ?? false }
    /// The path shown: a move being added counts at once.
    var shownPath: [String] { pending?.path ?? path }
    var currentNode: RepertoireNode? { RepertoireTree.node(at: path, in: tree) }

    var position: Position {
        if let pending { return pending.position }
        return Position(fen: currentNode?.fen ?? detail?.startFen ?? Position.startFEN) ?? .start
    }

    var lastMove: Move? {
        if let pending { return pending.move }
        return currentNode.flatMap { Move(uci: $0.uci) }
    }

    /// The side that may play on the board: nobody while a write is on its
    /// way, or on a repertoire kept for reading.
    var movableSide: Side? {
        guard phase == .ready, !isWriting, pending == nil else { return nil }
        return position.turn
    }

    var isOpponentToMove: Bool { position.turn != side }
    var canGoBack: Bool { !path.isEmpty && !isWriting }
    var canGoForward: Bool { !(RepertoireTree.children(at: path, in: tree) ?? []).isEmpty && !isWriting }

    /// The moves from the start to here, then the main continuation.
    var line: [(node: RepertoireNode, path: [String], isAhead: Bool)] {
        var result: [(RepertoireNode, [String], Bool)] = []
        var walked: [String] = []
        for node in RepertoireTree.nodes(along: path, in: tree) {
            walked.append(node.uci)
            result.append((node, walked, false))
        }
        for node in RepertoireTree.mainLine(from: path, in: tree) {
            walked.append(node.uci)
            result.append((node, walked, true))
        }
        return result
    }

    /// The moves of the repertoire first, then what is played here.
    var moves: [BuilderMove] {
        Self.moves(children: RepertoireTree.children(at: path, in: tree) ?? [], stats: stats, source: source)
    }

    var unanswered: Int { stats?.gaps.count ?? 0 }

    /// The band the Lichess numbers on screen are for.
    var ratingLabel: String? {
        guard let band = stats?.ratings ?? ratings else { return nil }
        return ratingBands.first { $0.ratings == band }?.label
    }

    static func moves(children: [RepertoireNode], stats: RepertoirePosition?, source: StatsSource) -> [BuilderMove] {
        // The players' numbers fall back on the masters' when Lichess could not be reached.
        let database: RepertoirePosition.Database? = switch source {
        case .players: stats?.lichess ?? stats?.masters
        case .masters: stats?.masters
        case .mine: nil
        }
        func stat(uci: String, san: String) -> BuilderMove.Stat? {
            if source == .mine {
                guard let mine = stats?.mine.first(where: { $0.uci == uci || $0.san == san }) else { return nil }
                return .init(
                    games: mine.games, frequency: mine.freq, first: mine.wins, draws: mine.draws, last: mine.losses,
                    isMine: true, opening: nil
                )
            }
            guard let move = database?.moves.first(where: { $0.uci == uci }) else { return nil }
            return .init(
                games: move.games, frequency: move.freq, first: move.white, draws: move.draws, last: move.black,
                isMine: false, opening: move.opening
            )
        }
        var rows = children.map { node in
            BuilderMove(
                san: node.san, uci: node.uci, inRepertoire: true, isUnanswered: false,
                glyph: RepertoireTree.glyph(node.nags), hasNote: !node.comments.isEmpty,
                movesBelow: node.descendantCount, stat: stat(uci: node.uci, san: node.san)
            )
        }
        let held = Set(children.map(\.uci))
        let gaps = Set(stats?.gaps.map(\.uci) ?? [])
        if source == .mine {
            for mine in stats?.mine ?? [] where mine.uci.map({ !held.contains($0) }) ?? !children.contains(where: { $0.san == mine.san }) {
                rows.append(BuilderMove(
                    san: mine.san, uci: mine.uci, inRepertoire: false, isUnanswered: mine.uci.map(gaps.contains) ?? false,
                    glyph: "", hasNote: false, movesBelow: 0, stat: stat(uci: mine.uci ?? "", san: mine.san)
                ))
            }
        } else {
            for move in database?.moves ?? [] where !held.contains(move.uci) {
                rows.append(BuilderMove(
                    san: move.san, uci: move.uci, inRepertoire: false, isUnanswered: gaps.contains(move.uci),
                    glyph: "", hasNote: false, movesBelow: 0, stat: stat(uci: move.uci, san: move.san)
                ))
            }
        }
        return rows
    }

    // MARK: Loading

    func load() async {
        do {
            detail = try await api.repertoire(id: id, token: token)
            path = RepertoireTree.longestPrefix(of: path, in: tree)
            phase = .ready
            loadStats(after: .zero)
        } catch is CancellationError {
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            phase = .failed(failure.message)
        }
    }

    /// Reads the repertoire again without leaving the screen: after a
    /// training session its progress has moved. A failure changes nothing.
    func refresh() async {
        guard phase == .ready, !isWriting, let fresh = try? await api.repertoire(id: id, token: token) else { return }
        detail = fresh
        path = RepertoireTree.longestPrefix(of: path, in: tree)
    }

    /// Lets the pending statistics request finish: tests wait on it.
    func statsSettled() async {
        await statsTask?.value
    }

    // MARK: Walking the tree

    func goTo(_ path: [String]) {
        guard !isWriting, RepertoireTree.node(at: path, in: tree) != nil || path.isEmpty else { return }
        move(to: path)
    }

    func goBack() {
        guard canGoBack else { return }
        move(to: Array(path.dropLast()))
    }

    /// One move down the main line.
    func goForward() {
        guard !isWriting, let next = RepertoireTree.children(at: path, in: tree)?.first else { return }
        move(to: path + [next.uci])
    }

    func goToStart() {
        guard !isWriting else { return }
        move(to: [])
    }

    private func move(to newPath: [String]) {
        guard newPath != path else { return }
        path = newPath
        loadStats(after: debounce)
    }

    func choose(ratings band: String) {
        guard band != (stats?.ratings ?? ratings) else { return }
        ratings = band
        loadStats(after: .zero)
    }

    func retryStats() {
        loadStats(after: .zero)
    }

    private func loadStats(after delay: Duration) {
        statsTask?.cancel()
        let key = StatsKey(path: path, ratings: ratings)
        if let known = cache[key] {
            stats = known
            statsPhase = .loaded
            statsTask = nil
            return
        }
        // The numbers of another position are never shown under this one.
        stats = nil
        statsPhase = .loading
        statsTask = Task { [weak self, api, token, id] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            do {
                let position = try await api.repertoirePosition(id: id, path: key.path, ratings: key.ratings, token: token)
                guard !Task.isCancelled, let self, self.path == key.path, self.ratings == key.ratings else { return }
                self.cache[key] = position
                self.stats = position
                self.ratingBands = position.ratingBands
                self.statsPhase = .loaded
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, let self, self.path == key.path else { return }
                let failure = error as? APIError ?? .unreadable
                if failure.isUnauthorized { self.onUnauthorized() }
                self.statsPhase = .failed(
                    failure.code == "rate_limited"
                        ? "Too many positions in a minute. The numbers are back in a moment."
                        : failure.message
                )
            }
        }
    }

    // MARK: Playing a move

    /// A move made on the board. Returns whether the board keeps showing it.
    func play(_ attempt: Move) -> Bool {
        guard phase == .ready, !isWriting, position.isLegal(position.normalized(attempt)) else { return false }
        let uci = position.normalized(attempt).uci
        if RepertoireTree.node(at: path + [uci], in: tree) != nil {
            move(to: path + [uci])
            return true
        }
        guard isEditable else {
            notice = Notice(text: "This repertoire is kept for reading: moves cannot be added to it.")
            return false
        }
        // Shown on the board at once; the server confirms it afterwards.
        guard let target = stage(uci) else { return false }
        Task { await send(target) }
        return true
    }

    /// A move chosen in the list: walks into it when the repertoire holds it,
    /// adds it otherwise.
    func play(uci: String) {
        guard let move = Move(uci: uci) else { return }
        _ = play(move)
    }

    /// Adds a move after the current position, and stands on it.
    func add(_ uci: String) async {
        guard let target = stage(uci) else { return }
        await send(target)
    }

    /// Puts a move on the board before it is sent. Nil when it cannot be played.
    private func stage(_ uci: String) -> [String]? {
        guard !isWriting, pending == nil, let move = Move(uci: uci) else { return nil }
        let before = position
        let normalized = before.normalized(move)
        guard let san = before.san(for: normalized), let after = before.playing(normalized) else { return nil }
        let target = path + [normalized.uci]
        pending = Pending(path: target, position: after, move: normalized, san: san)
        return target
    }

    private func send(_ target: [String]) async {
        await write(invalidating: [Array(target.dropLast())]) { api, id, token in
            try await api.addRepertoireLine(id: id, line: target, token: token)
        } then: { model in
            model.path = RepertoireTree.longestPrefix(of: target, in: model.tree)
        }
    }

    /// Adds a whole line from the start position, and stands at its end.
    func add(line: [String]) async {
        guard !isWriting, !line.isEmpty else { return }
        let prefixes = line.indices.map { Array(line.prefix($0)) }
        await write(invalidating: prefixes) { api, id, token in
            try await api.addRepertoireLine(id: id, line: line, token: token)
        } then: { model in
            model.path = RepertoireTree.longestPrefix(of: line, in: model.tree)
        }
    }

    /// Removes the current move and everything played after it.
    func removeCurrentMove() async {
        guard !isWriting, !path.isEmpty else { return }
        let removed = path
        let parent = Array(path.dropLast())
        await write(invalidating: [parent], below: removed) { api, id, token in
            try await api.removeRepertoireMove(id: id, path: removed, token: token)
        } then: { model in
            model.path = RepertoireTree.longestPrefix(of: parent, in: model.tree)
        }
    }

    /// Sets the note and the glyph of the current move; at the start, the
    /// note before the first move.
    func annotate(comment: String, glyph: GlyphChange) async {
        let target = path
        await write(invalidating: []) { api, id, token in
            try await api.annotateRepertoireMove(
                id: id, path: target, comment: comment, glyph: target.isEmpty ? .keep : glyph, token: token
            )
        } then: { _ in }
    }

    func importPGN(_ pgn: String) async -> Bool {
        var summary: String?
        let done = await write(invalidatingAll: true) { api, id, token in
            let result = try await api.importRepertoirePGN(id: id, pgn: pgn, token: token)
            summary = Self.importSummary(result)
            return result.repertoire
        } then: { model in
            model.path = []
        }
        if done, let summary { notice = Notice(text: summary) }
        return done
    }

    func seedFromGames() async -> Bool {
        var games = 0
        let done = await write(invalidatingAll: true) { api, id, token in
            let result = try await api.seedRepertoire(id: id, token: token)
            games = result.games
            return result.repertoire
        } then: { model in
            model.path = []
        }
        if done { notice = Notice(text: "Built from \(CDFormat.plural(games, "game")) of yours.") }
        return done
    }

    func rename(_ name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isWriting else { return false }
        isWriting = true
        defer { isWriting = false }
        do {
            try await api.renameRepertoire(id: id, name: name, token: token)
            detail = try await api.repertoire(id: id, token: token)
            return true
        } catch {
            await refused(error)
            return false
        }
    }

    /// "Imported 12 lines from 3 games, merged into one tree. 1 game starts
    /// from another position and was left out.": the site's sentence.
    static func importSummary(_ result: RepertoireImport) -> String {
        var text = "Imported \(CDFormat.plural(result.repertoire.lines, "line"))"
        if result.merged > 1 { text += " from \(CDFormat.count(result.merged)) games, merged into one tree" }
        text += "."
        if result.skipped > 0 {
            text += result.skipped == 1
                ? " 1 game starts from another position and was left out."
                : " \(CDFormat.count(result.skipped)) games start from another position and were left out."
        }
        return text
    }

    // MARK: Writing

    /// One change of the tree: sends it, takes the answer as the new tree,
    /// and forgets the statistics that the change made stale.
    @discardableResult
    private func write(
        invalidating paths: [[String]] = [],
        below removed: [String]? = nil,
        invalidatingAll: Bool = false,
        _ change: (any RepertoiresAPI & Sendable, String, String) async throws -> RepertoireDetail,
        then settle: (RepertoireBuilderModel) -> Void
    ) async -> Bool {
        guard !isWriting else { return false }
        isWriting = true
        notice = nil
        defer {
            isWriting = false
            pending = nil
        }
        do {
            detail = try await change(api, id, token)
            if invalidatingAll {
                cache = [:]
            } else {
                cache = cache.filter { key, _ in
                    if paths.contains(key.path) { return false }
                    if let removed, key.path.starts(with: removed) { return false }
                    return true
                }
            }
            pending = nil
            settle(self)
            path = RepertoireTree.longestPrefix(of: path, in: tree)
            loadStats(after: .zero)
            return true
        } catch {
            pending = nil
            await refused(error)
            return false
        }
    }

    /// A write that did not go through. The paywall opens the Premium sheet;
    /// a rule of the server (a lost concurrent write included) shows its
    /// sentence and the repertoire is read again, since it may have moved.
    private func refused(_ error: any Error) async {
        if error is CancellationError { return }
        let failure = error as? APIError ?? .unreadable
        if failure.isUnauthorized {
            onUnauthorized()
            return
        }
        notice = Notice(text: failure.message, isError: true)
        if failure.isPremiumRequired {
            showsPremium = true
            return
        }
        guard case .server = failure else { return }
        if let fresh = try? await api.repertoire(id: id, token: token) {
            detail = fresh
            cache = [:]
            path = RepertoireTree.longestPrefix(of: path, in: tree)
            loadStats(after: .zero)
        }
    }
}
