import ChessCore
import Foundation

// SYNTHETIC DATA. Nothing in this file was captured from the site: the
// repertoire and explorer operations are not served yet, so there is no
// answer to capture. `FixturePlayer` invents a signed-in player on the free
// plan, with one small repertoire, a few dozen games and opening statistics
// made up to look plausible. Its answers have the shapes of the contract
// (`contracts/openapi-v1.json`; a test checks them against its schemas) and
// follow the rules of the site as far as they are known from its source, so
// that the screens can be used, previewed and tested offline. It is what
// `FixtureAPI` answers with, in Debug builds on sample data only.
//
// Replace it with captured answers once the operations are served.

/// The invented player of the sample data. One per process, so a change made
/// on one screen is seen by the next, as with a server.
actor FixturePlayer {
    static let shared = FixturePlayer()
    /// A player of its own for the task at hand: tests run side by side, and
    /// each one starts from the first state.
    @TaskLocal static var scoped: FixturePlayer?
    static var current: FixturePlayer { scoped ?? shared }

    private var premium: Bool
    private var stored: [FixtureRepertoire] = []
    /// Progress keys (`positionKey|uci`) the player has learned, and those due.
    private var learned: Set<String> = []
    private var due: Set<String> = []
    private var learnedToday = 0
    private var created = 1
    private let games: [FixtureGame]

    init(premium: Bool? = nil) {
        #if DEBUG
            // `-CDFixturePremium YES`: the invented player has Premium.
            self.premium = premium ?? UserDefaults.standard.bool(forKey: "CDFixturePremium")
        #else
            self.premium = premium ?? false
        #endif
        games = FixtureData.games()
        let start = FixtureData.seed()
        stored = [start.repertoire]
        learned = start.learned
        due = start.due
    }

    // MARK: Repertoires

    private func canTrain(_ id: String) -> Bool {
        premium || stored.min { $0.createdAt < $1.createdAt }?.id == id
    }

    private func index(of id: String) throws -> Int {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw FixtureData.notFound }
        return index
    }

    private func owned(_ id: String) throws -> Int {
        let index = try index(of: id)
        guard canTrain(id) else { throw FixtureData.freeLimit }
        return index
    }

    private func progress(_ repertoire: FixtureRepertoire) -> DeckProgress {
        FixtureData.progress(FixtureData.trainingLines(repertoire), learned: learned, due: due)
    }

    private func card(_ repertoire: FixtureRepertoire) -> RepertoireCard {
        RepertoireCard(
            id: repertoire.id, name: repertoire.name, color: repertoire.color, deck: repertoire.deck,
            lines: RepertoireTree.lineCount(repertoire.tree), moves: RepertoireTree.moveCount(repertoire.tree),
            progress: progress(repertoire), editable: canTrain(repertoire.id), updatedAt: repertoire.updatedAt
        )
    }

    private func body(_ repertoire: FixtureRepertoire) -> RepertoireDetail {
        let lines = RepertoireTree.lineCount(repertoire.tree)
        return RepertoireDetail(
            id: repertoire.id, name: repertoire.name, color: repertoire.color, deck: repertoire.deck,
            lines: lines, moves: RepertoireTree.moveCount(repertoire.tree), progress: progress(repertoire),
            editable: canTrain(repertoire.id), updatedAt: repertoire.updatedAt, startFen: repertoire.startFen,
            tree: repertoire.tree, rootComment: repertoire.rootComment,
            pgn: FixturePGN.write(tree: repertoire.tree, rootComment: repertoire.rootComment),
            lineLimit: premium ? nil : max(FixtureData.freeLines, lines),
            pace: .init(perDay: FixtureData.perDay, newLeft: max(0, FixtureData.perDay - learnedToday))
        )
    }

    func list() -> RepertoireList {
        let cards = stored.sorted { $0.updatedAt > $1.updatedAt }.map(card)
        var keys: Set<String> = []
        for repertoire in stored {
            for line in FixtureData.trainingLines(repertoire) {
                for step in line.steps where step.mine && due.contains(step.key) { keys.insert(step.key) }
            }
        }
        let top = cards.max { $0.progress.dueMoves < $1.progress.dueMoves }
        return RepertoireList(repertoires: cards, totalDue: keys.count, top: top?.id, canCreate: premium || stored.isEmpty)
    }

    func detail(_ id: String) throws -> RepertoireDetail {
        body(stored[try index(of: id)])
    }

    func create(name: String, color: String) throws -> RepertoireDetail {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FixtureData.refused("Name cannot be empty.") }
        guard premium || stored.isEmpty else { throw FixtureData.freeLimit }
        created += 1
        let repertoire = FixtureRepertoire(
            id: "sample-\(created)", name: name, color: color == "BLACK" ? "BLACK" : "WHITE",
            startFen: Position.startFEN, tree: [], rootComment: "", createdAt: .now, updatedAt: .now
        )
        stored.append(repertoire)
        return body(repertoire)
    }

    func rename(_ id: String, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FixtureData.refused("Name cannot be empty.") }
        let index = try owned(id)
        stored[index].name = name
    }

    func delete(_ id: String) throws {
        stored.remove(at: try owned(id))
    }

    /// Writes a new tree, under the free plan's allowance: 20 lines, or what
    /// the repertoire already holds.
    private func write(_ tree: [RepertoireNode], rootComment: String? = nil, at index: Int) throws -> RepertoireDetail {
        let allowance = max(FixtureData.freeLines, RepertoireTree.lineCount(stored[index].tree))
        guard premium || RepertoireTree.lineCount(tree) <= allowance else { throw FixtureData.freeLimit }
        stored[index].tree = tree
        if let rootComment { stored[index].rootComment = rootComment }
        stored[index].updatedAt = .now
        return body(stored[index])
    }

    func addLine(_ id: String, line: [String]) throws -> RepertoireDetail {
        guard !line.isEmpty else { throw FixtureData.refused("Play at least one move.") }
        let index = try owned(id)
        guard let next = RepertoireTree.adding(line: line, to: stored[index].tree, startFen: stored[index].startFen)
        else { throw FixtureData.refused("That move is not legal in this position.") }
        return next.added == 0 ? body(stored[index]) : try write(next.tree, at: index)
    }

    func remove(_ id: String, path: [String]) throws -> RepertoireDetail {
        guard !path.isEmpty else { throw FixtureData.refused("Name the move to remove.") }
        let index = try owned(id)
        guard let next = RepertoireTree.removing(path: path, from: stored[index].tree) else { throw FixtureData.moveNotFound }
        return try write(next, at: index)
    }

    func annotate(_ id: String, path: [String], comment: String?, glyph: GlyphChange) throws -> RepertoireDetail {
        if case let .set(nag) = glyph, !(1...6).contains(nag) { throw FixtureData.refused("Unknown annotation.") }
        let index = try owned(id)
        let text = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            if case .set = glyph { throw FixtureData.refused("Only a move can carry an annotation glyph.") }
            guard let text else { return body(stored[index]) }
            return try write(stored[index].tree, rootComment: text, at: index)
        }
        let next = RepertoireTree.updating(path: path, in: stored[index].tree) { node in
            let comments = text.map { $0.isEmpty ? [] : [$0] } ?? node.comments
            let nags: [Int] = switch glyph {
            case .keep: node.nags
            case .clear: []
            case let .set(nag): [nag]
            }
            return node.with(comments: comments, nags: nags)
        }
        guard let next else { throw FixtureData.moveNotFound }
        return try write(next, at: index)
    }

    func importPGN(_ id: String, pgn: String) throws -> RepertoireImport {
        let read = FixturePGN.read(pgn)
        guard read.merged > 0, !read.tree.isEmpty else { throw FixtureData.refused("No game found in that PGN.") }
        let index = try owned(id)
        let detail = try write(read.tree, rootComment: read.rootComment, at: index)
        return RepertoireImport(repertoire: detail, merged: read.merged, skipped: read.skipped)
    }

    func seed(_ id: String) throws -> RepertoireSeed {
        let index = try owned(id)
        let side: Side = stored[index].color == "BLACK" ? .black : .white
        let own = games.filter { $0.side == side }
        guard !own.isEmpty else {
            throw FixtureData.refused("No \(side == .white ? "white" : "black") games imported yet to seed from.")
        }
        // The lines played at least twice, cut after eight half-moves.
        var counts: [[String]: Int] = [:]
        for game in own { counts[Array(game.line.prefix(8)), default: 0] += 1 }
        var tree: [RepertoireNode] = []
        for (line, count) in counts.sorted(by: { $0.value > $1.value || ($0.value == $1.value && $0.key.lexicographicallyPrecedes($1.key)) })
        where count >= 2 {
            let ucis = FixtureData.uciLine(line.joined(separator: " "))
            if let next = RepertoireTree.adding(line: ucis, to: tree, startFen: stored[index].startFen) { tree = next.tree }
        }
        guard !tree.isEmpty else { throw FixtureData.refused("Could not build a tree from those games.") }
        return RepertoireSeed(repertoire: try write(tree, at: index), games: own.count)
    }

    // MARK: Training

    func session(_ id: String, mode requested: SessionMode?) throws -> CourseSession {
        let repertoire = stored[try index(of: id)]
        guard canTrain(id) else {
            throw APIError.server(
                status: 403, code: "premium_required",
                message: "Free includes training your first repertoire. Premium trains them all."
            )
        }
        let lines = FixtureData.trainingLines(repertoire)
        let progress = FixtureData.progress(lines, learned: learned, due: due)
        let mode = requested ?? (progress.dueMoves > 0 ? .review : .learn)
        var learn: [String] = []
        var review: [CourseSession.ReviewItem] = []
        if mode == .learn {
            let left = max(0, FixtureData.perDay - learnedToday)
            learn = lines.filter { line in line.steps.contains { $0.mine && !learned.contains($0.key) } }
                .prefix(left).map(\.id)
        } else {
            var asked: Set<String> = []
            for line in lines {
                let test = line.steps.indices.filter { index in
                    let step = line.steps[index]
                    return step.mine && due.contains(step.key) && asked.insert(step.key).inserted
                }
                if !test.isEmpty { review.append(.init(lineId: line.id, test: test)) }
            }
        }
        let used = Set(learn + review.map(\.lineId))
        let sessionLines = lines.filter { used.contains($0.id) }
        let known = Set(sessionLines.flatMap(\.steps).filter { $0.mine && learned.contains($0.key) }.map(\.key))
        return CourseSession(
            deck: repertoire.deck, mode: mode, color: repertoire.color, lines: sessionLines, learn: learn,
            review: review, known: known.sorted(), next: nil, chapterTitles: [repertoire.name], narration: nil
        )
    }

    /// `POST /training/grades` for a repertoire deck.
    func record(deck: String, grades: [MoveGrade]) {
        guard let repertoire = stored.first(where: { $0.deck == deck }) else { return }
        let lines = FixtureData.trainingLines(repertoire)
        let newBefore = FixtureData.progress(lines, learned: learned, due: due).newLines
        for grade in grades {
            guard let position = Position(fen: grade.fen) else { continue }
            let key = "\(position.positionKey)|\(grade.uci)"
            learned.insert(key)
            if grade.grade == .good { due.remove(key) } else { due.insert(key) }
        }
        learnedToday += max(0, newBefore - FixtureData.progress(lines, learned: learned, due: due).newLines)
    }

    // MARK: A position of the builder

    func position(_ id: String, path: [String], ratings: String?) throws -> RepertoirePosition {
        let repertoire = stored[try index(of: id)]
        guard var position = Position(fen: repertoire.startFen) else { throw FixtureData.notFound }
        var san: [String] = []
        var canonical: [String] = []
        for uci in path {
            guard let move = Move(uci: uci), let name = position.san(for: move), let next = position.playing(move) else {
                throw APIError.server(
                    status: 400, code: "invalid_request", message: "That line is not legal from the start of the repertoire."
                )
            }
            canonical.append(position.normalized(move).uci)
            san.append(name)
            position = next
        }
        let children = RepertoireTree.children(at: canonical, in: repertoire.tree)
        let covered = (children ?? []).map(\.uci)
        let band = ratings ?? "1000"
        let masters = FixtureData.database(position: position, san: san, total: 60000, decay: 2.2, draws: 0.34)
        let lichess = FixtureData.database(
            position: position, san: san, total: 1_600_000 + (Int(band) ?? 0) * 300, decay: 2.6, draws: 0.05
        )
        let side: Side = repertoire.color == "BLACK" ? .black : .white
        let opponentToMove = position.turn != side
        // Free: the most recent games only (lib/explorer/limits.ts).
        let own = games.filter { $0.side == side }.prefix(premium ? Int.max : FixtureData.freeGames)
        let mine = FixtureData.aggregate(Array(own), at: san).map { move in
            RepertoirePosition.Mine(
                san: move.san, uci: position.move(san: move.san).map { position.normalized($0).uci },
                games: move.games, freq: Double(move.games) / Double(max(1, move.total)), score: move.score,
                wins: move.wins, draws: move.draws, losses: move.losses
            )
        }
        // lib/repertoire/gaps.ts: replies played at least 5% of the time the tree has no answer to.
        let gaps = !opponentToMove ? [] : lichess.moves.filter { $0.freq >= 0.05 && !covered.contains($0.uci) }
            .sorted { $0.freq > $1.freq }
            .map { RepertoirePosition.Gap(san: $0.san, uci: $0.uci, freq: $0.freq, opening: $0.opening) }
        return RepertoirePosition(
            fen: position.fen, path: path, san: san, inRepertoire: children != nil, covered: covered,
            masters: masters, lichess: lichess, ratings: band, ratingBands: FixtureData.ratingBands, mine: mine,
            opponentToMove: opponentToMove, gaps: gaps,
            advice: FixtureData.advice(ply: path.count, games: lichess.total, yourTurn: !opponentToMove)
        )
    }

    // MARK: Games against the repertoire

    func adherence(_ id: String) throws -> RepertoireAdherence {
        let repertoire = stored[try index(of: id)]
        guard premium else {
            throw APIError.server(
                status: 403, code: "premium_required", message: "Checking your games against a repertoire is part of Premium."
            )
        }
        let side: Side = repertoire.color == "BLACK" ? .black : .white
        let rows = games.filter { $0.side == side }.prefix(60).map { game in
            let check = FixtureData.adherence(line: game.line, tree: repertoire.tree, side: side)
            return RepertoireAdherence.Game(
                gameId: game.summary.id, opponent: game.opponent, result: game.result, playedAt: game.summary.playedAt,
                url: nil, status: check.status, pliesFollowed: check.plies, deviation: check.deviation
            )
        }
        return RepertoireAdherence(
            hasTree: !repertoire.tree.isEmpty,
            followed: rows.count { $0.status == "followed" },
            deviated: rows.count { $0.status == "deviated" },
            games: Array(rows)
        )
    }

    // MARK: Explorer

    private var explorable: [FixtureGame] {
        Array(games.prefix(premium ? Int.max : FixtureData.freeGames))
    }

    func explorerSummary() -> ExplorerSummary {
        let limit: Int? = premium ? nil : FixtureData.freeGames
        return ExplorerSummary(
            white: explorable.count { $0.side == .white }, black: explorable.count { $0.side == .black },
            imported: games.count, limit: limit, capped: limit.map { games.count > $0 } ?? false, hasLinkedAccount: true
        )
    }

    func explorerPosition(path: [String], filters: ExplorerFilters, games wanted: Int?) throws -> ExplorerPosition {
        var position = Position.start
        for san in path {
            guard let move = position.move(san: san), let next = position.playing(move) else {
                throw APIError.server(
                    status: 400, code: "invalid_request", message: "That line is not legal from the start position."
                )
            }
            position = next
        }
        let dataset = explorable.filter { FixtureData.matches($0, filters) }
        let reaching = dataset.filter { $0.line.starts(with: path) }
        let moves = FixtureData.aggregate(dataset, at: path).map { move in
            ExplorerPosition.Move(
                san: move.san, uci: position.move(san: move.san).map { position.normalized($0).uci }, games: move.games,
                wins: move.wins, draws: move.draws, losses: move.losses, score: move.score, sampleGameId: move.sample
            )
        }
        return ExplorerPosition(
            side: filters.side == .black ? "black" : "white", path: path, fen: position.fen, total: dataset.count,
            reaching: reaching.count, activeFilters: filters.activeCount, limit: premium ? nil : FixtureData.freeGames,
            moves: moves, endOfData: path.count >= FixtureData.openingPlies - 1,
            games: reaching.prefix(min(50, wanted ?? 10)).map(\.summary),
            insights: FixtureData.insights(dataset, side: filters.side)
        )
    }

    /// A game of the invented player, for the game screen.
    func game(id: String) -> FixtureGame? {
        games.first { $0.summary.id == id }
    }
}

nonisolated struct FixtureRepertoire: Sendable {
    let id: String
    var name: String
    let color: String
    let startFen: String
    var tree: [RepertoireNode]
    var rootComment: String
    let createdAt: Date
    var updatedAt: Date

    var deck: String { "repertoire:\(id)" }
}

nonisolated struct FixtureGame: Sendable {
    let summary: GameSummary
    /// The opening moves in SAN, as ChessCore writes them.
    let line: [String]
    let side: Side
    /// "win", "draw" or "loss", from the player's side.
    let result: String

    var opponent: String { side == .white ? summary.black : summary.white }
    var opponentElo: Int? { side == .white ? summary.blackElo : summary.whiteElo }
}

/// The invented data and the site's rules the sample player follows.
nonisolated enum FixtureData {
    static let freeLines = 20
    static let freeGames = 100
    static let perDay = 3
    /// The site stores the first 40 half-moves of each game.
    static let openingPlies = 40

    static let freeLimit = APIError.server(
        status: 403, code: "premium_required",
        message: "Free includes your first repertoire with up to 20 lines. Keep training it, or choose Premium for more. Existing work remains available to read and export."
    )
    static let notFound = APIError.server(status: 404, code: "not_found", message: "Repertoire not found.")
    static let moveNotFound = APIError.server(status: 404, code: "not_found", message: "That move is not in the repertoire.")

    static func refused(_ message: String) -> APIError {
        .server(status: 422, code: "request_failed", message: message)
    }

    // MARK: The repertoire (invented)

    /// The first state of the player: one repertoire, its first two lines
    /// known, a few of their moves due again.
    static func seed() -> (repertoire: FixtureRepertoire, learned: Set<String>, due: Set<String>) {
        var tree: [RepertoireNode] = []
        for line in repertoireLines {
            if let next = RepertoireTree.adding(line: uciLine(line), to: tree, startFen: Position.startFEN) { tree = next.tree }
        }
        for (line, note, nags) in repertoireNotes {
            tree = RepertoireTree.updating(path: uciLine(line), in: tree) { $0.with(comments: [note], nags: nags) } ?? tree
        }
        let repertoire = FixtureRepertoire(
            id: "sample-italian", name: "Italian Game", color: "WHITE", startFen: Position.startFEN, tree: tree,
            rootComment: "Open with the king's pawn, develop fast, castle early.",
            createdAt: Date(timeIntervalSinceNow: -40 * 86400), updatedAt: Date(timeIntervalSinceNow: -2 * 86400)
        )
        var learned: Set<String> = []
        var due: Set<String> = []
        let lines = trainingLines(repertoire)
        for line in lines.prefix(2) {
            for step in line.steps where step.mine { learned.insert(step.key) }
        }
        if let first = lines.first {
            for step in first.steps.suffix(6) where step.mine { due.insert(step.key) }
        }
        return (repertoire, learned, due)
    }

    static let repertoireLines = [
        "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3",
        "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3",
        "e4 e5 Nf3 d6 d4 exd4 Nxd4",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4",
        "e4 e6 d4 d5 Nc3",
        "e4 c6 d4 d5 Nc3",
    ]

    static let repertoireNotes: [(line: String, note: String, nags: [Int])] = [
        ("e4 e5 Nf3 Nc6 Bc4", "The bishop looks at f7, the weakest square in Black's camp.", []),
        ("e4 e5 Nf3 Nc6 Bc4 Bc5 c3", "Prepares d4 with a pawn behind it.", [1]),
        ("e4 e5 Nf3 Nc6 Bc4 Nf6 d3", "Quiet and safe: no Fried Liver tricks to remember.", []),
    ]

    /// "e4 e5 Nf3" as UCI moves from the start position; stops at a move the rules refuse.
    static func uciLine(_ san: String) -> [String] {
        var position = Position.start
        var line: [String] = []
        for token in san.split(separator: " ") {
            guard let move = position.move(san: String(token)), let next = position.playing(move) else { break }
            line.append(position.normalized(move).uci)
            position = next
        }
        return line
    }

    /// The same line as ChessCore writes its moves.
    static func sanLine(_ san: String) -> [String] {
        var position = Position.start
        var line: [String] = []
        for token in san.split(separator: " ") {
            guard let move = position.move(san: String(token)), let name = position.san(for: move),
                  let next = position.playing(move)
            else { break }
            line.append(name)
            position = next
        }
        return line
    }

    // MARK: Training lines (lib/training/lines.ts)

    /// One line per path to a leaf, depth first; the player's own moves are
    /// the cards, keyed by the position before the move and the move.
    static func trainingLines(_ repertoire: FixtureRepertoire) -> [TrainingLine] {
        let mine: Side = repertoire.color == "BLACK" ? .black : .white
        var lines: [TrainingLine] = []
        func walk(_ nodes: [RepertoireNode], fenBefore: String, steps: [LineStep]) {
            for node in nodes {
                let before = Position(fen: fenBefore) ?? .start
                let step = LineStep(
                    san: node.san, uci: node.uci, fenBefore: fenBefore, fenAfter: node.fen,
                    key: "\(before.positionKey)|\(node.uci)", mine: before.turn == mine,
                    comments: node.comments, shapes: node.shapes, ply: node.ply
                )
                if node.children.isEmpty {
                    lines.append(TrainingLine(
                        id: "0.\(lines.count)", chapter: 0, index: lines.count, startFen: repertoire.startFen,
                        steps: steps + [step], side: nil
                    ))
                } else {
                    walk(node.children, fenBefore: node.fen, steps: steps + [step])
                }
            }
        }
        walk(repertoire.tree, fenBefore: repertoire.startFen, steps: [])
        return lines
    }

    static func progress(_ lines: [TrainingLine], learned: Set<String>, due: Set<String>) -> DeckProgress {
        var keys: Set<String> = []
        var learnedLines = 0, dueLines = 0, solid = 0
        for line in lines {
            let cards = line.steps.filter(\.mine).map(\.key)
            keys.formUnion(cards)
            let known = cards.allSatisfy(learned.contains)
            let isDue = cards.contains(where: due.contains)
            if known { learnedLines += 1 }
            if isDue { dueLines += 1 }
            if known, !isDue { solid += 1 }
        }
        return DeckProgress(
            lines: lines.count, learned: learnedLines, newLines: lines.count - learnedLines, dueLines: dueLines,
            solidLines: solid, dueMoves: keys.intersection(due).count, moves: keys.count
        )
    }

    // MARK: Opening statistics (invented numbers)

    static let ratingBands: [RepertoirePosition.RatingBand] = [
        ("0", "Under 1000"), ("1000", "1000–1200"), ("1200", "1200–1400"), ("1400", "1400–1600"),
        ("1600", "1600–1800"), ("1800", "1800–2000"), ("2000", "2000–2200"), ("2200", "2200–2500"), ("2500", "2500+"),
    ].map { .init(ratings: $0.0, label: $0.1) }

    private static let book: [String: [(san: String, share: Double, opening: String?)]] = [
        "": [("e4", 0.52, "King's Pawn"), ("d4", 0.30, "Queen's Pawn"), ("Nf3", 0.08, "Zukertort Opening"), ("c4", 0.06, "English Opening")],
        "e4": [
            ("e5", 0.44, "King's Pawn Game"), ("c5", 0.22, "Sicilian Defense"), ("e6", 0.10, "French Defense"),
            ("c6", 0.08, "Caro-Kann Defense"), ("d5", 0.07, "Scandinavian Defense"), ("d6", 0.04, "Pirc Defense"),
        ],
        "e4 e5": [
            ("Nf3", 0.68, "King's Knight Opening"), ("Bc4", 0.14, "Bishop's Opening"), ("Nc3", 0.07, "Vienna Game"),
            ("f4", 0.05, "King's Gambit"), ("d4", 0.04, "Center Game"),
        ],
        "e4 e5 Nf3": [
            ("Nc6", 0.62, "King's Knight Opening"), ("d6", 0.16, "Philidor Defense"), ("Nf6", 0.12, "Petrov's Defense"),
            ("Qf6", 0.04, nil), ("f6", 0.03, "Damiano Defense"),
        ],
        "e4 e5 Nf3 Nc6": [
            ("Bc4", 0.46, "Italian Game"), ("Bb5", 0.24, "Ruy Lopez"), ("d4", 0.15, "Scotch Game"),
            ("Nc3", 0.10, "Three Knights Opening"),
        ],
        "e4 e5 Nf3 Nc6 Bc4": [
            ("Bc5", 0.40, "Giuoco Piano"), ("Nf6", 0.30, "Two Knights Defense"), ("h6", 0.12, "Anti-Fried Liver Defense"),
            ("d6", 0.08, nil), ("Be7", 0.05, "Hungarian Defense"),
        ],
        "e4 e5 Nf3 Nc6 Bc4 Bc5": [
            ("c3", 0.34, "Giuoco Piano"), ("d3", 0.26, "Giuoco Pianissimo"), ("O-O", 0.18, nil), ("Nc3", 0.12, nil),
            ("b4", 0.05, "Evans Gambit"),
        ],
        "e4 e5 Nf3 Nf6": [("Nxe5", 0.48, "Petrov's Defense"), ("Nc3", 0.24, "Three Knights Game"), ("d4", 0.12, nil), ("d3", 0.10, nil)],
        "e4 c5": [
            ("Nf3", 0.58, "Sicilian Defense"), ("Nc3", 0.16, "Closed Sicilian"), ("Bc4", 0.10, "Bowdler Attack"),
            ("d4", 0.08, "Smith-Morra Gambit"), ("c3", 0.05, "Alapin Variation"),
        ],
        "e4 c5 Nf3": [("d6", 0.34, nil), ("Nc6", 0.32, nil), ("e6", 0.22, nil), ("g6", 0.06, nil)],
        "e4 e6": [("d4", 0.72, "French Defense"), ("Nf3", 0.12, nil), ("d3", 0.06, nil), ("Nc3", 0.05, nil)],
        "e4 c6": [("d4", 0.66, "Caro-Kann Defense"), ("Nf3", 0.14, nil), ("Nc3", 0.10, nil), ("Bc4", 0.05, nil)],
    ]

    /// A database at one position: the tabled moves where the position is in
    /// the little book above, else a handful of sensible legal moves.
    static func database(
        position: Position, san path: [String], total base: Int, decay: Double, draws: Double
    ) -> RepertoirePosition.Database {
        let total = Int(Double(base) / pow(decay, Double(path.count)))
        let listed = book[path.joined(separator: " ")] ?? fallback(position)
        let moves = listed.compactMap { entry -> RepertoirePosition.Move? in
            guard let move = position.move(san: entry.san), let san = position.san(for: move) else { return nil }
            let games = Int((Double(total) * entry.share).rounded())
            guard games > 0 else { return nil }
            // A stable number between 0.44 and 0.54 for White's share of the decided games.
            let seed = Double(abs((path.joined() + san).unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 1009 }))
            let whiteShare = 0.44 + (seed / 1009) * 0.10
            let drawn = Int(Double(games) * draws)
            let white = Int(Double(games - drawn) * whiteShare)
            let black = games - drawn - white
            return RepertoirePosition.Move(
                san: san, uci: position.normalized(move).uci, games: games, white: white, draws: drawn, black: black,
                freq: entry.share, whiteScore: (Double(white) + Double(drawn) / 2) / Double(games), opening: entry.opening
            )
        }
        return .init(total: total, moves: moves)
    }

    private static func fallback(_ position: Position) -> [(san: String, share: Double, opening: String?)] {
        let shares = [0.42, 0.27, 0.16, 0.09, 0.06]
        let ranked = position.legalMoves().compactMap { move -> (san: String, weight: Int)? in
            guard let san = position.san(for: move), let piece = position[move.from] else { return nil }
            var weight = 0
            if position.isCapture(move) { weight += 4 }
            if position.isCastling(move) { weight += 5 }
            // Knights towards the centre, centre pawns two squares, then bishops.
            if piece.kind == .knight { weight += (2...5).contains(move.to.file) ? 4 : 1 }
            if piece.kind == .bishop { weight += 2 }
            if piece.kind == .pawn, (2...5).contains(move.to.file) {
                weight += abs(move.to.rank - move.from.rank) == 2 ? 4 : 2
            }
            if piece.kind == .king, !position.isCastling(move) { weight -= 4 }
            // Not onto a square a pawn takes on.
            if piece.kind != .pawn, pawnAttacks(move.to, in: position) { weight -= 6 }
            return (san, weight)
        }
        .sorted { $0.weight > $1.weight || ($0.weight == $1.weight && $0.san < $1.san) }
        return zip(ranked, shares).map { ($0.san, $1, nil) }
    }

    private static func pawnAttacks(_ square: Square, in position: Position) -> Bool {
        let forward = position.turn == .white ? 1 : -1
        return [-1, 1].contains { side in
            Square(file: square.file + side, rank: square.rank + forward)
                .map { position[$0] == Piece(position.turn.opposite, .pawn) } ?? false
        }
    }

    /// lib/repertoire/line-depth.ts: is the line worth extending?
    static func advice(ply: Int, games: Int, yourTurn: Bool) -> RepertoirePosition.Advice {
        let moveNumber = ply / 2 + 1
        let ending = yourTurn ? "Add your move, then end the line here." : "Your line can end here."
        let count = games.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
        func advice(_ kind: String, _ title: String, _ detail: String) -> RepertoirePosition.Advice {
            .init(kind: kind, title: title, detail: detail, moveNumber: moveNumber)
        }
        if games == 0 { return advice("stop", "Out of book", "No games reach this position. \(ending)") }
        if games < 50 {
            let reach = games == 1 ? "game reaches" : "games reach"
            return advice("stop", "Rare position", "Only \(count) \(reach) it, so you will seldom meet it. \(ending)")
        }
        if ply >= 24 {
            return advice("stop", "Deep enough", "Past move 12, most repertoires stop unless the line is forcing. \(ending)")
        }
        if games < 500 || ply >= 16 {
            return advice(
                "consider", "Nearly done",
                "\(count) games reach this position. Cover the main reply or two, then wrap the line up."
            )
        }
        return advice(
            "keep", "Keep going",
            "\(count) games reach this position. \(yourTurn ? "Add your move." : "Add answers to the main replies.")"
        )
    }

    // MARK: The player's games (invented)

    private static let templates: [(side: Side, line: String, results: String, opening: String, eco: String)] = [
        (.white, "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3", "WWLWD", "Italian Game: Giuoco Piano", "C54"),
        (.white, "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3 d6", "WLWW", "Italian Game: Two Knights Defense", "C55"),
        (.white, "e4 e5 Nf3 Nc6 Bc4 h6 d4 exd4 Nxd4", "WW", "Italian Game: Anti-Fried Liver Defense", "C50"),
        (.white, "e4 e5 Nf3 d6 d4 exd4 Nxd4 Nf6 Nc3", "WDW", "Philidor Defense", "C41"),
        (.white, "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4", "LD", "Petrov's Defense", "C42"),
        (.white, "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", "LLWL", "Sicilian Defense: Najdorf Variation", "B90"),
        (.white, "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6", "LD", "Sicilian Defense: Accelerated Dragon", "B34"),
        (.white, "e4 e6 d4 d5 Nc3 Bb4 e5 c5", "WL", "French Defense: Winawer Variation", "C16"),
        (.white, "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5", "WW", "Caro-Kann Defense: Classical Variation", "B18"),
        (.white, "e4 d5 exd5 Qxd5 Nc3 Qa5 d4", "WW", "Scandinavian Defense", "B01"),
        (.white, "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6", "L", "Ruy Lopez", "C78"),
        (.white, "e4 e5 Bc4 Nf6 d3 Bc5", "D", "Bishop's Opening", "C24"),
        (.black, "e4 c6 d4 d5 e5 Bf5 Nf3 e6", "WWDLW", "Caro-Kann Defense: Advance Variation", "B12"),
        (.black, "e4 c6 d4 d5 exd5 cxd5 Bd3 Nc6", "WLWD", "Caro-Kann Defense: Exchange Variation", "B13"),
        (.black, "e4 c6 Nf3 d5 Nc3 Bg4", "WLW", "Caro-Kann Defense: Two Knights Attack", "B11"),
        (.black, "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7", "LLDW", "Queen's Gambit Declined", "D53"),
        (.black, "d4 d5 Bf4 Nf6 e3 c5 c3 Nc6", "LWL", "London System", "D02"),
        (.black, "d4 Nf6 c4 e6 Nf3 d5", "DW", "Queen's Gambit Declined", "D37"),
        (.black, "c4 e5 Nc3 Nf6", "L", "English Opening", "A22"),
    ]

    /// The games, newest first. Dates are counted back from today.
    static func games(now: Date = .now) -> [FixtureGame] {
        var drafts: [(side: Side, line: [String], result: Character, opening: String, eco: String)] = []
        for template in templates {
            let line = sanLine(template.line)
            for result in template.results { drafts.append((template.side, line, result, template.opening, template.eco)) }
        }
        // Mixed, so that neither colour nor opening comes in blocks.
        let order = drafts.indices.sorted { ($0 * 29) % 53 < ($1 * 29) % 53 }
        return order.enumerated().map { rank, index in
            let draft = drafts[index]
            let outcome = draft.result == "W" ? "win" : draft.result == "D" ? "draw" : "loss"
            let whiteWon = (draft.side == .white) == (outcome == "win")
            let score = outcome == "draw" ? "1/2-1/2" : whiteWon ? "1-0" : "0-1"
            let opponent = "opponent_\(100 + index)"
            let opponentElo = 880 + (index * 37) % 240
            let mine = 940 + (index * 13) % 60
            let timeClass = index % 7 == 0 ? "BULLET" : index % 4 == 0 ? "BLITZ" : "RAPID"
            let summary = GameSummary(
                id: "sample-game-\(index + 1)", source: index % 3 == 0 ? "LICHESS" : "CHESSCOM",
                white: draft.side == .white ? "sample_player" : opponent,
                black: draft.side == .white ? opponent : "sample_player",
                whiteElo: draft.side == .white ? mine : opponentElo, blackElo: draft.side == .white ? opponentElo : mine,
                result: score, timeClass: timeClass, timeControl: timeClass == "RAPID" ? "600" : timeClass == "BLITZ" ? "300" : "60",
                eco: draft.eco, opening: draft.opening, userColor: draft.side == .white ? "white" : "black",
                playedAt: now.addingTimeInterval(-Double(rank) * 2.4 * 86400 - 5400), ply: 48 + (index * 7) % 40,
                rated: index % 9 != 0, starred: false, reviewed: false
            )
            return FixtureGame(summary: summary, line: draft.line, side: draft.side, result: outcome)
        }
    }

    static func matches(_ game: FixtureGame, _ filters: ExplorerFilters) -> Bool {
        let summary = game.summary
        guard game.side == filters.side else { return false }
        if !filters.timeClasses.isEmpty, !filters.timeClasses.contains(summary.timeClass) { return false }
        if filters.rated == .rated, !summary.rated { return false }
        if filters.rated == .casual, summary.rated { return false }
        let day = ExplorerFilters.day(summary.playedAt)
        if let from = filters.dateFrom, day < from { return false }
        if let to = filters.dateTo, day > to { return false }
        if let min = filters.opponentMin, (game.opponentElo ?? 0) < min { return false }
        if let max = filters.opponentMax, (game.opponentElo ?? Int.max) > max { return false }
        if let source = filters.source, summary.source != source.rawValue { return false }
        return true
    }

    struct MoveCount: Sendable {
        let san: String
        var games = 0
        var wins = 0
        var draws = 0
        var losses = 0
        let sample: String
        var total = 0

        var score: Double { (Double(wins) + Double(draws) / 2) / Double(max(1, games)) }
    }

    /// lib/explorer/aggregate.ts: the moves played from the position reached
    /// by `path`, most played first.
    static func aggregate(_ games: [FixtureGame], at path: [String]) -> [MoveCount] {
        var counts: [String: MoveCount] = [:]
        var total = 0
        for game in games where game.line.count > path.count && game.line.starts(with: path) {
            let san = game.line[path.count]
            var count = counts[san] ?? MoveCount(san: san, sample: game.summary.id)
            count.games += 1
            switch game.result {
            case "win": count.wins += 1
            case "draw": count.draws += 1
            default: count.losses += 1
            }
            counts[san] = count
            total += 1
        }
        return counts.values.map { count in
            var count = count
            count.total = total
            return count
        }
        .sorted { $0.games > $1.games || ($0.games == $1.games && $0.san < $1.san) }
    }

    /// lib/explorer/insights.ts: the line played most, the best one and the leak.
    static func insights(_ games: [FixtureGame], side: Side) -> ExplorerPosition.Insights {
        guard !games.isEmpty else { return .init(mostPlayed: nil, best: nil, leak: nil) }
        let total = games.count
        let minGames = max(3, Int((Double(total) * 0.05).rounded()))
        let parity = side == .white ? 1 : 0
        var byPrefix: [[String]: (games: Int, points: Double)] = [:]
        for game in games {
            let points = game.result == "win" ? 1 : game.result == "draw" ? 0.5 : 0
            for length in stride(from: 1, through: min(10, game.line.count), by: 1) where length % 2 == parity {
                let key = Array(game.line.prefix(length))
                let old = byPrefix[key] ?? (0, 0)
                byPrefix[key] = (old.games + 1, old.points + points)
            }
        }
        struct Candidate {
            let path: [String]
            let games: Int
            let score: Double
            let smoothed: Double
        }
        let candidates = byPrefix.filter { $0.value.games >= minGames }.map { path, value in
            Candidate(
                path: path, games: value.games, score: value.points / Double(value.games),
                smoothed: (value.points + 1) / Double(value.games + 2)
            )
        }
        .sorted { $0.path.joined(separator: " ") < $1.path.joined(separator: " ") }
        guard !candidates.isEmpty else { return .init(mostPlayed: nil, best: nil, leak: nil) }
        func insight(_ candidate: Candidate) -> ExplorerPosition.Insight {
            let line = candidate.path.enumerated()
                .map { $0.offset.isMultiple(of: 2) ? "\($0.offset / 2 + 1).\($0.element)" : $0.element }
                .joined(separator: " ")
            return .init(path: candidate.path, line: line, games: candidate.games, score: candidate.score)
        }
        let share = max(minGames, Int((Double(total) * 0.25).rounded(.up)))
        let deep = candidates.filter { $0.games >= share }
            .max { ($0.path.count, $0.games) < ($1.path.count, $1.games) }
        guard let main = deep ?? candidates.max(by: { $0.games < $1.games }) else {
            return .init(mostPlayed: nil, best: nil, leak: nil)
        }
        let others = candidates
            .filter { !main.path.starts(with: $0.path) }
            .sorted { ($0.smoothed, $0.games, $0.path.count) > ($1.smoothed, $1.games, $1.path.count) }
        let best = others.first.flatMap { $0.score > 0.5 ? $0 : nil }
        let leak = others.last.flatMap { $0.score < 0.5 && $0.path != best?.path ? $0 : nil }
        return .init(mostPlayed: insight(main), best: best.map(insight), leak: leak.map(insight))
    }

    /// lib/repertoire/adherence.ts: where a game left the repertoire.
    static func adherence(
        line: [String], tree: [RepertoireNode], side: Side
    ) -> (status: String, plies: Int, deviation: RepertoireAdherence.Deviation?) {
        var nodes = tree
        var plies = 0
        for (index, san) in line.enumerated() {
            let ply = index + 1
            let mine = (side == .white) == !ply.isMultiple(of: 2)
            let match = nodes.first { $0.san == san }
            if mine {
                if nodes.isEmpty { return (plies > 0 ? "out_of_book" : "no_overlap", plies, nil) }
                if match == nil {
                    return ("deviated", plies, .init(ply: ply, moveNumber: (ply + 1) / 2, expected: nodes.map(\.san), played: san))
                }
            }
            guard let match else { return (plies > 0 ? "out_of_book" : "no_overlap", plies, nil) }
            plies += 1
            nodes = match.children
        }
        return ("followed", plies, nil)
    }
}

/// A PGN writer and reader with variations, for the sample data only: the
/// server writes and reads the real ones.
nonisolated enum FixturePGN {
    static func write(tree: [RepertoireNode], rootComment: String) -> String {
        var text = rootComment.isEmpty ? "" : "{\(rootComment)} "
        text += moves(tree, opens: true)
        return text.trimmingCharacters(in: .whitespaces) + (tree.isEmpty ? "*" : " *")
    }

    private static func token(_ node: RepertoireNode, opens: Bool) -> String {
        var text = RepertoireTree.number(ply: node.ply, opensRow: opens).map { $0.replacingOccurrences(of: "…", with: "...") + " " } ?? ""
        text += node.san
        for nag in node.nags { text += " $\(nag)" }
        for comment in node.comments { text += " {\(comment)}" }
        return text
    }

    private static func moves(_ siblings: [RepertoireNode], opens: Bool) -> String {
        guard let main = siblings.first else { return "" }
        var text = token(main, opens: opens)
        for alternative in siblings.dropFirst() {
            text += " (" + token(alternative, opens: true)
            let rest = moves(alternative.children, opens: false)
            text += (rest.isEmpty ? "" : " " + rest) + ")"
        }
        let rest = moves(main.children, opens: siblings.count > 1 || !main.comments.isEmpty)
        return text + (rest.isEmpty ? "" : " " + rest)
    }

    /// Every game merged into one tree. Games from another start position are skipped.
    static func read(_ pgn: String) -> (tree: [RepertoireNode], rootComment: String, merged: Int, skipped: Int) {
        var tree: [RepertoireNode] = []
        var rootComment = ""
        var merged = 0
        var skipped = 0
        for game in games(pgn) {
            if game.customStart {
                skipped += 1
                continue
            }
            var added = false
            // The line being read, and the lines left open by "(".
            var line: [String] = []
            var stack: [[String]] = []
            for token in tokens(game.body) {
                switch token {
                case "(":
                    stack.append(line)
                    line = Array(line.dropLast())
                case ")":
                    line = stack.popLast() ?? line
                default:
                    if token.hasPrefix("{") {
                        let note = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                        if line.isEmpty {
                            if rootComment.isEmpty { rootComment = note }
                        } else if let next = RepertoireTree.updating(path: line, in: tree, { $0.with(comments: [note], nags: $0.nags) }) {
                            tree = next
                        }
                    } else if token.hasPrefix("$"), let nag = Int(token.dropFirst()), (1...6).contains(nag) {
                        tree = RepertoireTree.updating(path: line, in: tree) { $0.with(comments: $0.comments, nags: [nag]) } ?? tree
                    } else if let uci = uci(token, after: line), let next = RepertoireTree.adding(
                        line: line + [uci], to: tree, startFen: Position.startFEN
                    ) {
                        tree = next.tree
                        line.append(uci)
                        added = true
                    }
                }
            }
            if added { merged += 1 }
        }
        return (tree, rootComment, merged, skipped)
    }

    private static func uci(_ san: String, after line: [String]) -> String? {
        var position = Position.start
        for uci in line {
            guard let move = Move(uci: uci), let next = position.playing(move) else { return nil }
            position = next
        }
        return position.move(san: san).map { position.normalized($0).uci }
    }

    private static func games(_ pgn: String) -> [(body: String, customStart: Bool)] {
        var games: [(body: String, customStart: Bool)] = []
        var body = ""
        var customStart = false
        var inHeaders = false
        func close() {
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { games.append((body, customStart)) }
            body = ""
            customStart = false
        }
        for raw in pgn.split(whereSeparator: \.isNewline) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("["), text.hasSuffix("]") {
                if !inHeaders { close() }
                inHeaders = true
                if text.hasPrefix("[FEN "), !text.contains(Position.startFEN) { customStart = true }
            } else {
                inHeaders = false
                body += text + " "
            }
        }
        close()
        return games
    }

    /// Movetext to tokens: moves, "(", ")", "{comments}" and "$n" glyphs.
    private static func tokens(_ body: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var comment: String?
        func flush() {
            let word = current.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            current = ""
            guard !word.isEmpty, Int(word) == nil, !["1-0", "0-1", "1/2-1/2", "*"].contains(word) else { return }
            // "12.Nf3" and "12...Nf6" carry their number; "0-0" is castling, not a number.
            let san = word.hasPrefix("0-0") ? Substring(word) : word.drop { $0.isNumber || $0 == "." }
            if !san.isEmpty { tokens.append(String(san)) }
        }
        for character in body {
            if comment != nil {
                if character == "}" {
                    tokens.append("{\(comment ?? "")}")
                    comment = nil
                } else {
                    comment?.append(character)
                }
                continue
            }
            switch character {
            case "{":
                flush()
                comment = ""
            case "(", ")":
                flush()
                tokens.append(String(character))
            case " ", "\t", "\n", "\r":
                flush()
            default:
                current.append(character)
            }
        }
        flush()
        return tokens
    }
}
