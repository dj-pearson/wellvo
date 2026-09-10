import Foundation
import SwiftData
import Network
import Supabase
import os

/// Manages offline check-in queuing and syncing.
/// When the device is offline, check-ins are persisted to SwiftData.
/// When connectivity returns, queued check-ins are synced to Supabase.
@MainActor
final class OfflineCheckInService: ObservableObject {
    static let shared = OfflineCheckInService()

    @Published var isOnline = true
    @Published var pendingCount = 0

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "net.wellvo.networkmonitor")
    private var modelContainer: ModelContainer?
    /// A single long-lived context reused across queue/sync/count operations
    /// instead of constructing a fresh `ModelContext(container)` per call (which
    /// defeats SwiftData's caching). The service is `@MainActor`, so all access
    /// is serialized on the main actor.
    private var sharedContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false

    init() {
        setupModelContainer()
        pruneStaleQueuedCheckIns()
        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
        syncTask?.cancel()
    }

    // MARK: - Queue a Check-In (Offline)

    func queueCheckIn(
        familyId: UUID,
        receiverId: UUID,
        mood: Mood?,
        source: CheckInSource,
        slotKey: String? = nil
    ) throws {
        // Never treat an unpersisted check-in as "queued, will sync". If the
        // SwiftData store failed to initialize (disk full, migration error), the
        // old `guard let … else { return }` returned silently — the caller reported
        // success, nothing was saved, and on reconnect there was no row to sync, so
        // the owner escalated falsely. Recover the container if we can; otherwise
        // throw so the failure surfaces to the user instead of vanishing.
        let context = try ensureContext()

        // Clear out anything left from a previous day first, so a device that
        // stayed offline across midnight doesn't keep reporting yesterday's
        // unsent row as pending — and doesn't hold it for a replay that would
        // land as today's check-in.
        pruneStaleQueuedCheckIns()

        // Per-slot, per-day dedup: an anxious receiver who doesn't see immediate
        // confirmation may tap "I'm OK" several times while offline. Each tap
        // must NOT enqueue a separate row — otherwise sync would create N
        // duplicate check-ins for the same window.
        //
        // The dedup key is (receiver, family, local day, slotKey), NOT the day
        // alone. Before US-IOS137 it was the day alone, which silently dropped
        // every window after the first for a receiver on a multi-window custom
        // schedule (US-IOS048): the morning tap queued a row, the evening tap
        // matched that row and returned, the UI still said "saved, will sync",
        // and the owner escalated on an evening window the receiver had in fact
        // answered. False escalation is the one failure this whole file exists
        // to prevent, so the slot has to be part of the identity.
        //
        // `slotKey` is nil for single-window schedules, which is the common
        // case and behaves exactly as before: one row per receiver per day.
        //
        // The slot comparison is done in Swift rather than inside #Predicate.
        // Optional-to-optional equality against a captured value is awkward to
        // express in a SwiftData predicate, and the fetch is already narrowed to
        // one receiver's unsynced rows for today — at most a handful.
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let dedupDescriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { row in
                row.familyId == familyId &&
                row.receiverId == receiverId &&
                !row.synced &&
                row.createdAt >= startOfDay
            }
        )
        if let sameDay = try? context.fetch(dedupDescriptor),
           Self.isAlreadyQueued(slotKey: slotKey, amongQueuedSlots: sameDay.map(\.slotKey)) {
            return
        }

        let offlineCheckIn = OfflineCheckIn(
            familyId: familyId,
            receiverId: receiverId,
            mood: mood,
            source: source,
            slotKey: slotKey
        )
        context.insert(offlineCheckIn)

        do {
            try context.save()
            updatePendingCount()
        } catch {
            Log.offline.error("Failed to queue check-in: \(error.localizedDescription, privacy: .public)")
            throw DailyOKError.unknown(error)
        }
    }

    /// Attempt to check in — queues locally if offline, sends directly if online.
    /// `slotKey` (US-IOS048) tags which scheduled window this check-in satisfies
    /// and is now carried through the offline queue as well (US-IOS137).
    ///
    /// It used to be dropped on the offline path, to avoid adding an attribute
    /// to the SwiftData model. That traded a migration for a false-escalation
    /// bug: with the slot missing, the queue's day-level dedup swallowed every
    /// window after the first, and the receiver's later windows were reported as
    /// missed. Carrying the slot costs one optional attribute, which SwiftData
    /// migrates lightly, and old rows keep nil — day-level, exactly as before.
    func performCheckIn(familyId: UUID, mood: Mood? = nil, source: CheckInSource = .app, slotKey: String? = nil) async throws -> CheckIn? {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            throw CheckInError.notAuthenticated
        }

        let receiverId = session.user.id

        if isOnline {
            do {
                let checkIn = try await NetworkRetry.execute {
                    try await CheckInService.shared.checkIn(familyId: familyId, mood: mood, source: source, slotKey: slotKey)
                }
                return checkIn
            } catch {
                // Decide offline-vs-error from the ERROR itself, not the
                // asynchronously-updated `isOnline` flag. NWPathMonitor often
                // hasn't flipped `isOnline` to false yet when the radio drops
                // mid-request, which previously meant a genuine-offline check-in
                // was surfaced as a raw error instead of being queued (the exact
                // false-escalation risk we want to avoid).
                if Self.isConnectivityError(error) {
                    try queueCheckIn(
                        familyId: familyId,
                        receiverId: receiverId,
                        mood: mood,
                        source: source,
                        slotKey: slotKey
                    )
                    throw NetworkError.offline
                }
                throw error
            }
        } else {
            try queueCheckIn(
                familyId: familyId,
                receiverId: receiverId,
                mood: mood,
                source: source,
                slotKey: slotKey
            )
            return nil
        }
    }

    /// Whether a new offline check-in for `slotKey` is already covered by what is
    /// queued. `queuedSlots` is the slot of every unsynced row this receiver has
    /// for this family today.
    ///
    /// Slot identity, not day identity (US-IOS137). Two taps answering the same
    /// window are a duplicate and the second must not enqueue a row; two taps
    /// answering different windows of a multi-window schedule are two real
    /// check-ins and both must survive, or the owner escalates on a window the
    /// receiver actually answered.
    ///
    /// nil is a slot value like any other — it means "day-level", which is what
    /// a single-window schedule produces and what rows written before this
    /// shipped carry — so two day-level taps still dedup against each other.
    nonisolated static func isAlreadyQueued(slotKey: String?, amongQueuedSlots queuedSlots: [String?]) -> Bool {
        queuedSlots.contains(slotKey)
    }

    /// Whether a queued row has outlived the day it was meant to answer.
    ///
    /// The sync path replays a queued check-in through
    /// `process-checkin-response`, which stamps `checked_in_at` server-side with
    /// `now()` — the request carries no client timestamp (see US-IOS147). So a
    /// row queued on Monday and synced on Thursday is not recorded as Monday's
    /// check-in: it is recorded as a *Thursday* check-in the receiver never
    /// made. The owner's dashboard then reads "checked in today" for someone who
    /// has not touched their phone in three days.
    ///
    /// False reassurance is strictly worse than the false escalation the rest of
    /// this file guards against — the escalation is the product working. So a
    /// row whose local day has passed is dropped rather than replayed. Monday's
    /// window already escalated when it was missed; nothing is recovered by
    /// fabricating a Thursday check-in, and the receiver's real safety signal is
    /// not overwritten.
    ///
    /// Same-day rows (the overwhelmingly common case: a tunnel, a dead cell,
    /// airplane mode for an hour) sync exactly as before.
    nonisolated static func isStale(
        queuedAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(queuedAt, inSameDayAs: now)
    }

    /// True when the error represents a loss of connectivity (as opposed to a
    /// server/auth/client error). Used to decide whether to optimistically queue
    /// a check-in for later sync.
    static func isConnectivityError(_ error: Error) -> Bool {
        if error is NetworkError { return true }
        // `respondToCheckIn` (and other callers) re-wrap thrown errors as
        // `DailyOKError.network(_)` / `.unknown(_)` before they reach here, so a
        // genuine connectivity failure would otherwise bridge to an NSError with
        // the DailyOKError domain (not NSURLErrorDomain) and be misclassified as
        // a hard error — leaving the check-in un-queued and falsely escalating.
        // Unwrap one level and re-test.
        if let appError = error as? DailyOKError {
            switch appError {
            case .network(let inner), .unknown(let inner):
                return isConnectivityError(inner)
            default:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive:
            return true
        default:
            return false
        }
    }

    // MARK: - Sync Queued Check-Ins

    func syncPendingCheckIns() async {
        // Re-entrancy guard: this is triggered from the network monitor, scene
        // phase, and loadStatus simultaneously. Without a guard, two syncs could
        // process the same pending set concurrently and double-submit.
        guard let context = sharedContext, isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Resolve the signed-in user once. The check-in is recorded for the
        // session user server-side, so only sync rows that belong to them.
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        let currentUserId = session.user.id

        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { !$0.synced },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        var syncedAny = false

        for offlineCheckIn in pending {
            // A row that has outlived its day would be recorded as a check-in
            // for TODAY (the server stamps `checked_in_at` itself), so replaying
            // it tells the owner the receiver is fine when they may not be.
            // Drop it instead — see `isStale`.
            if Self.isStale(queuedAt: offlineCheckIn.createdAt) {
                Log.offline.notice("Dropping stale queued check-in from a previous day rather than replaying it as today's")
                context.delete(offlineCheckIn)
                try? context.save()
                continue
            }

            // Leave rows queued by a different (now signed-out) account for when
            // that user signs back in — the edge function records for the
            // current session and would otherwise attribute it to the wrong user.
            // Such rows are still bounded: once the day turns they are stale and
            // the branch above removes them.
            guard offlineCheckIn.receiverId == currentUserId else { continue }

            do {
                // Route through the SAME edge-function path as an online
                // check-in (`process-checkin-response`). That handler dedups by
                // the receiver's local calendar day — returning the existing
                // row instead of inserting a duplicate — and clears any pending
                // checkin_requests. The previous raw `insert` bypassed that
                // dedup and could create duplicate check-ins (corrupting
                // streaks, consistency, and exported reports).
                let mood = offlineCheckIn.mood.flatMap(Mood.init(rawValue:))
                let source = CheckInSource(rawValue: offlineCheckIn.source) ?? .app
                _ = try await CheckInService.shared.checkIn(
                    familyId: offlineCheckIn.familyId,
                    mood: mood,
                    source: source,
                    // Replay the window this check-in actually answered, so the
                    // server dedups against the right slot rather than folding
                    // the day's windows into one (US-IOS137). nil for rows
                    // queued by a single-window schedule, and for rows written
                    // before this shipped — both mean day-level, as before.
                    slotKey: offlineCheckIn.slotKey
                )

                // Delete rather than flag. Nothing reads a synced row — every
                // query in this file filters on `!synced` — so flagging them
                // grew the store for the life of the install and left other
                // people's check-in history (receiver id, family id, mood) on
                // the device forever. The row has done its job; remove it.
                context.delete(offlineCheckIn)
                try context.save()
                syncedAny = true
            } catch {
                if NetworkRetry.isNonRetryable(error) {
                    // Deterministic server rejection (e.g. 400/403/404) — this row
                    // will NEVER succeed, so dead-letter it (mark synced so it
                    // leaves the queue) and keep going. Otherwise one poison row
                    // would stall every later queued check-in forever (US-IOS099).
                    Log.offline.error("Dropping un-syncable queued check-in: \(error.localizedDescription, privacy: .public)")
                    context.delete(offlineCheckIn)
                    try? context.save()
                    continue
                }
                Log.offline.error("Sync failed (will retry): \(error.localizedDescription, privacy: .public)")
                // Transient (connectivity / 5xx): stop and retry the rest of the
                // queue on the next trigger.
                break
            }
        }

        updatePendingCount()

        // Let any view model observing sync completion (e.g. ReceiverHomeView,
        // DashboardView) re-query status so the UI reflects the synced rows
        // without waiting for the next scene-phase change.
        if syncedAny {
            NotificationCenter.default.post(name: OfflineCheckInService.didSyncCheckIns, object: nil)
        }
    }

    /// Raised when the offline queue's backing store can't be opened, so a failed
    /// online check-in can't be persisted for later sync. Surfaced to the caller
    /// instead of being swallowed.
    enum OfflineQueueError: LocalizedError {
        case storeUnavailable
        var errorDescription: String? {
            String(localized: "Couldn't save your check-in on this device. Please try again when you have a connection.")
        }
    }

    static let didSyncCheckIns = Notification.Name("OfflineCheckInService.didSyncCheckIns")
    /// Posted (on the main actor) when the network transitions from offline to
    /// online, so services holding time-sensitive state can refresh.
    static let connectivityRestored = Notification.Name("OfflineCheckInService.connectivityRestored")

    // MARK: - Private

    private func setupModelContainer() {
        do {
            let container = try ModelContainer(for: OfflineCheckIn.self)
            modelContainer = container
            sharedContext = ModelContext(container)
        } catch {
            Log.offline.error("Failed to create SwiftData container: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Return the shared model context, retrying container creation once if the
    /// initial setup at `init` failed transiently. Throws `OfflineQueueError`
    /// rather than returning `nil` so a caller never silently drops a check-in it
    /// believes it queued (which would falsely escalate the owner).
    private func ensureContext() throws -> ModelContext {
        if let context = sharedContext { return context }
        setupModelContainer()
        if let context = sharedContext { return context }
        throw DailyOKError.unknown(OfflineQueueError.storeUnavailable)
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                // Sync when coming back online, and broadcast the transition so
                // other services (e.g. the heartbeat) can refresh state that
                // went stale during the offline stretch.
                if wasOffline && path.status == .satisfied {
                    await self?.syncPendingCheckIns()
                    NotificationCenter.default.post(name: OfflineCheckInService.connectivityRestored, object: nil)
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Remove queued rows that have outlived the day they were meant to answer.
    ///
    /// Sync drops them too, but sync only runs when the device is online and
    /// signed in. Pruning here keeps `pendingCount` — which drives the "waiting
    /// to send" UI — from advertising a check-in that will never be sent.
    private func pruneStaleQueuedCheckIns() {
        guard let context = sharedContext else { return }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { $0.createdAt < startOfToday }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for row in stale { context.delete(row) }
        do {
            try context.save()
            Log.offline.notice("Pruned \(stale.count, privacy: .public) queued check-in(s) left over from a previous day")
        } catch {
            Log.offline.error("Failed to prune stale queued check-ins: \(error.localizedDescription, privacy: .public)")
        }
        updatePendingCount()
    }

    private func updatePendingCount() {
        guard let context = sharedContext else { return }
        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { !$0.synced }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
