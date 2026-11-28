import ChessCore
import Foundation
import Observation

/// Today's Daily 5, from opening to the streak moving (the site's
/// `components/habit/daily-session.tsx`). The server picks the positions,
/// keeps the player's local day from the time zone sent, and moves the
/// streak; the app solves the positions and reports.
@Observable
final class DailySessionModel {
    enum Phase: Equatable {
        case loading
        /// The positions, one after the other.
        case solving
        /// The last position is solved; the session is being closed.
        case closing
        /// Closed: the streak as the server moved it.
        case finished(DailyCompletion)
        /// The answers are saved but the session could not be closed.
        case closeFailed(String)
        /// Today's session was done before: nothing to solve unless five more are asked for.
        case doneEarlier
        /// Nothing to solve: no mistake due and no puzzle to serve.
        case empty
        case failed(String)
    }

    /// What the offer of a reminder, after the session, has become.
    enum ReminderOffer: Equatable {
        case offered, saving, set(hour: Int), dismissed, failed
    }

    private(set) var phase: Phase = .loading
    private(set) var plan: DailyPlan?
    var drill = PositionDrill(items: [])
    private(set) var reminderOffer: ReminderOffer?

    private let api: any ChessDeskAPI
    private let token: String
    private let timeZone: String
    /// The hour the reminder is offered at: now, as on the site.
    let offerHour: Int

    init(api: any ChessDeskAPI, token: String, timeZone: TimeZone = .current, now: Date = .now) {
        self.api = api
        self.token = token
        self.timeZone = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        offerHour = calendar.component(.hour, from: now)
    }

    var source: DailySource { plan?.source?.value ?? .mistakes }
    var streak: DailyStreak? { plan?.streak }

    /// Reads today's positions; `again` asks for five more after the day's session.
    func load(again: Bool = false) async {
        phase = .loading
        reminderOffer = nil
        do {
            let plan = try await api.daily(again: again, token: token)
            self.plan = plan
            if plan.items.isEmpty {
                phase = plan.doneToday && !again ? .doneEarlier : .empty
                return
            }
            drill = PositionDrill(items: plan.items)
            phase = .solving
            // Opening the session records the time zone; the session works without it.
            _ = try? await api.startDaily(
                DailySessionRequest(tz: timeZone, source: source, total: plan.items.count), token: token
            )
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(APIError.unreadable.message)
        }
    }

    /// Records a resolved position: a mistake's attempt goes to its schedule.
    func record(_ result: MistakeResult, for item: TrainItem) async {
        guard item.kind.value == .mistake else { return }
        _ = try? await api.recordMistakeAttempt(item.id, result: result, token: token)
    }

    /// The recording of the last resolved position (and the closing after the
    /// last one), running behind the board. Tests wait for it.
    private(set) var pending: Task<Void, Never>?

    /// A move on the board, answered at once. A resolved position is recorded
    /// behind it, and the session is closed after the last one.
    @discardableResult
    func play(_ move: Move) -> PositionDrill.Outcome {
        guard phase == .solving, let item = drill.item else { return .ignored }
        let outcome = drill.play(move)
        if case let .resolved(result) = outcome {
            let closes = drill.isComplete
            if closes { phase = .closing }
            pending = Task {
                await record(result, for: item)
                if closes { await close() }
            }
        }
        return outcome
    }

    /// Closes the day's session; also the retry after a failure.
    func close() async {
        phase = .closing
        do {
            let completion = try await api.completeDaily(
                DailyCompletionRequest(
                    tz: timeZone, source: source, total: drill.items.count, solved: drill.solvedFirstTry
                ),
                token: token
            )
            reminderOffer = completion.offerReminder ? .offered : nil
            phase = .finished(completion)
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .closeFailed(error.message)
        } catch {
            phase = .closeFailed(APIError.unreadable.message)
        }
    }

    // MARK: Reminder offer

    /// One email a day at the hour the session was finished.
    func acceptReminder() async {
        reminderOffer = .saving
        do {
            let reminder = try await api.setReminder(
                ReminderRequest(channel: .email, hour: offerHour, tz: timeZone), token: token
            )
            reminderOffer = .set(hour: reminder.hour ?? offerHour)
        } catch {
            reminderOffer = .failed
        }
    }

    func dismissReminder() async {
        reminderOffer = .dismissed
        try? await api.dismissReminderOffer(token: token)
    }
}
