import Foundation
import Observation

/// The player's repertoires and what is due in them.
@Observable
final class RepertoiresModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var list: RepertoireList?
    /// A change the server refused, in its words.
    var notice: String?
    var showsPremium = false

    private let api: any RepertoiresAPI & Sendable
    private let token: String
    private let onUnauthorized: () -> Void

    init(api: any RepertoiresAPI & Sendable, token: String, onUnauthorized: @escaping () -> Void = {}) {
        self.api = api
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    var repertoires: [RepertoireCard] { list?.repertoires ?? [] }
    /// The repertoire the server would train first.
    var top: RepertoireCard? { repertoires.first { $0.id == list?.top } }

    func load() async {
        do {
            list = try await api.repertoires(token: token)
            phase = .ready
        } catch is CancellationError {
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            // What is on screen stays when a refresh fails.
            if list == nil { phase = .failed(failure.message) }
        }
    }

    /// Creates an empty repertoire. Throws what the server answered, so the
    /// form can show it; the paywall opens the Premium sheet.
    func create(name: String, color: String) async throws -> RepertoireDetail {
        do {
            let created = try await api.createRepertoire(name: name, color: color, token: token)
            await load()
            return created
        } catch let failure as APIError {
            if failure.isUnauthorized { onUnauthorized() }
            if failure.isPremiumRequired { showsPremium = true }
            throw failure
        }
    }

    func rename(_ repertoire: RepertoireCard, to name: String) async {
        await change { api, token in try await api.renameRepertoire(id: repertoire.id, name: name, token: token) }
    }

    func delete(_ repertoire: RepertoireCard) async {
        await change { api, token in try await api.deleteRepertoire(id: repertoire.id, token: token) }
    }

    private func change(_ work: (any RepertoiresAPI & Sendable, String) async throws -> Void) async {
        notice = nil
        do {
            try await work(api, token)
        } catch is CancellationError {
            return
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { onUnauthorized() }
            if failure.isPremiumRequired { showsPremium = true }
            notice = failure.message
        }
        // Read again either way: a refusal may mean the list had moved.
        await load()
    }
}

extension RepertoireCard {
    /// "12 due", "3 new lines" or "Up to date", as the site's list says it.
    var status: (text: String, isDue: Bool) {
        if progress.dueMoves > 0 { return ("\(CDFormat.count(progress.dueMoves)) due", true) }
        if progress.newLines > 0 { return ("\(CDFormat.plural(progress.newLines, "new line", "new lines"))", false) }
        return ("Up to date", false)
    }

    /// Share of the lines learned, 0…1.
    var learnedShare: Double {
        progress.lines == 0 ? 0 : Double(progress.learned) / Double(progress.lines)
    }
}
