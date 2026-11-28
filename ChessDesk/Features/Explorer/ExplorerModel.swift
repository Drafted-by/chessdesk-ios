import ChessCore
import Foundation
import Observation

/// The opening explorer of the player's own games: which colour, which
/// filters, where in the tree. The server answers one position at a time.
@Observable
final class ExplorerModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var summary: ExplorerSummary?
    /// The moves from the start position, in SAN as the server writes them.
    private(set) var path: [String] = []
    private(set) var filters = ExplorerFilters()
    /// The position on screen. While another one loads, this one stays.
    private(set) var position: ExplorerPosition?
    private(set) var isLoadingPosition = false
    private(set) var positionFailure: String?
    var showsPremium = false

    private let api: any ExplorerAPI & Sendable
    private let token: String
    private let onUnauthorized: () -> Void
    private var positionTask: Task<Void, Never>?

    init(api: any ExplorerAPI & Sendable, token: String, onUnauthorized: @escaping () -> Void = {}) {
        self.api = api
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    // MARK: Reading the state

    var side: Side { filters.side }
    var sideToMove: Side { path.count.isMultiple(of: 2) ? .white : .black }
    var canGoBack: Bool { !path.isEmpty }
    /// With one move played from here there is no choice to make.
    var onlyMove: ExplorerPosition.Move? { position?.moves.count == 1 ? position?.moves.first : nil }

    /// The position shown belongs to the path and the filters asked for.
    var isCurrent: Bool {
        guard let position else { return false }
        return position.path == path && position.side == (filters.side == .black ? "black" : "white") && !isLoadingPosition
    }

    func games(as side: Side) -> Int {
        guard let summary else { return 0 }
        return side == .white ? summary.white : summary.black
    }

    // MARK: Loading

    func load() async {
        do {
            let summary = try await api.explorerSummary(token: token)
            self.summary = summary
            // The colour with games, when the default one has none.
            if games(as: filters.side) == 0, games(as: filters.side.opposite) > 0 { filters.side = filters.side.opposite }
            phase = .ready
            if !summary.isEmpty { await loadPosition() }
        } catch is CancellationError {
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            phase = .failed(failure.message)
        }
    }

    /// Lets the position being read arrive: tests wait on it.
    func settled() async {
        await positionTask?.value
    }

    // MARK: Walking

    func push(_ san: String) {
        guard position?.endOfData != true else { return }
        go(to: path + [san])
    }

    func back() {
        guard canGoBack else { return }
        go(to: Array(path.dropLast()))
    }

    /// Keeps the first `count` moves of the line.
    func cut(to count: Int) {
        go(to: Array(path.prefix(max(0, count))))
    }

    func go(to newPath: [String]) {
        guard newPath != path else { return }
        path = newPath
        reload()
    }

    // MARK: Filters

    /// The other colour is another tree: the walk starts again.
    func choose(side: Side) {
        guard side != filters.side else { return }
        filters.side = side
        path = []
        reload()
    }

    /// The filters narrow the games; the position is kept, as on the site.
    func apply(_ new: ExplorerFilters) {
        guard new != filters else { return }
        let sideChanged = new.side != filters.side
        filters = new
        if sideChanged { path = [] }
        reload()
    }

    func clearFilters() {
        apply(filters.cleared)
    }

    func retry() {
        reload()
    }

    private func reload() {
        positionTask?.cancel()
        // Said at once, so the rows of the position being left stop taking taps.
        isLoadingPosition = true
        positionFailure = nil
        positionTask = Task { [weak self] in await self?.loadPosition() }
    }

    private func loadPosition() async {
        let wantedPath = path
        let wantedFilters = filters
        isLoadingPosition = true
        positionFailure = nil
        do {
            let position = try await api.explorerPosition(path: wantedPath, filters: wantedFilters, games: nil, token: token)
            guard !Task.isCancelled, wantedPath == path, wantedFilters == filters else { return }
            self.position = position
            isLoadingPosition = false
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, wantedPath == path, wantedFilters == filters else { return }
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            isLoadingPosition = false
            positionFailure = failure.message
        }
    }
}

extension ExplorerPosition.Move {
    /// The score as the site colours it: good from 55%, poor under 48%.
    enum Tone { case good, even, poor }

    var tone: Tone {
        let percent = score * 100
        return percent >= 55 ? .good : percent >= 48 ? .even : .poor
    }

    var percent: Int { Int((score * 100).rounded()) }
}
