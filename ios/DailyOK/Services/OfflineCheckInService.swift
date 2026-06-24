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
        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
        syncTask?.cancel()
    }

    // MARK: - Queue a Check-In (Offline)

    func queueCheckIn(familyId: UUID, receiverId: UUID, mood: Mood?, source: CheckInSource) throws {
        guard let context = sharedContext else { return }

        // Per-day dedup: an anxious receiver who doesn't see immediate
        // confirmation may tap "I'm OK" several times while offline. Each tap
        // must NOT enqueue a separate row — otherwise sync would create N
        // duplicate check-ins for the same day. If an unsynced row already
        // exists for this receiver+family on the same local day, no-op.
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let dedupDescriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { row in
                row.familyId == familyId &&
                row.receiverId == receiverId &&
                !row.synced &&
                row.createdAt >= startOfDay
            }
        )
        if let existing = try? context.fetch(dedupDescriptor), !existing.isEmpty {
            return
        }

        let offlineCheckIn = OfflineCheckIn(
            familyId: familyId,
            receiverId: receiverId,
            mood: mood,
            source: source
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
    /// `slotKey` (US-IOS048) tags which scheduled window an online check-in
    /// satisfies; it's intentionally dropped on the offline-queued path (a
    /// later-synced check-in resolves to day-level), so no on-device migration
    /// of the offline queue is needed.
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
                    try queueCheckIn(familyId: familyId, receiverId: receiverId, mood: mood, source: source)
                    throw NetworkError.offline
                }
                throw error
            }
        } else {
            try queueCheckIn(familyId: familyId, receiverId: receiverId, mood: mood, source: source)
            return nil
        }
    }

    /// True when the error represents a loss of connectivity (as opposed to a
    /// server/auth/client error). Used to decide whether to optimistically queue
    /// a check-in for later sync.
    static func isConnectivityError(_ error: Error) -> Bool {
        if error is NetworkError { return true }
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
            // Leave rows queued by a different (now signed-out) account for when
            // that user signs back in — the edge function records for the
            // current session and would otherwise attribute it to the wrong user.
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
                    source: source
                )

                offlineCheckIn.synced = true
                try context.save()
                syncedAny = true
            } catch {
                Log.offline.error("Sync failed: \(error.localizedDescription, privacy: .public)")
                // Stop and retry on the next trigger. A connectivity error means
                // the network dropped again; any other error (server/auth) will
                // also be retried rather than dropping the queued check-in.
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

    static let didSyncCheckIns = Notification.Name("OfflineCheckInService.didSyncCheckIns")

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

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                // Sync when coming back online
                if wasOffline && path.status == .satisfied {
                    await self?.syncPendingCheckIns()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func updatePendingCount() {
        guard let context = sharedContext else { return }
        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { !$0.synced }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
