import Foundation
import SwiftData
import Network
import Supabase

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
    private var syncTask: Task<Void, Never>?

    init() {
        setupModelContainer()
        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
        syncTask?.cancel()
    }

    // MARK: - Queue a Check-In (Offline)

    func queueCheckIn(familyId: UUID, receiverId: UUID, mood: Mood?, source: CheckInSource) {
        guard let container = modelContainer else { return }

        let context = ModelContext(container)
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
            print("Failed to queue offline check-in: \(error.localizedDescription)")
        }
    }

    /// Attempt to check in — queues locally if offline, sends directly if online.
    func performCheckIn(familyId: UUID, mood: Mood? = nil, source: CheckInSource = .app) async throws -> CheckIn? {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            throw CheckInError.notAuthenticated
        }

        let receiverId = session.user.id

        if isOnline {
            do {
                let checkIn = try await NetworkRetry.execute {
                    try await CheckInService.shared.checkIn(familyId: familyId, mood: mood, source: source)
                }
                return checkIn
            } catch {
                // If network fails at this point, queue offline
                queueCheckIn(familyId: familyId, receiverId: receiverId, mood: mood, source: source)
                throw NetworkError.offline
            }
        } else {
            queueCheckIn(familyId: familyId, receiverId: receiverId, mood: mood, source: source)
            return nil
        }
    }

    // MARK: - Sync Queued Check-Ins

    func syncPendingCheckIns() async {
        guard let container = modelContainer, isOnline else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { !$0.synced },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for offlineCheckIn in pending {
            do {
                _ = try await SupabaseService.shared.client
                    .from("checkins")
                    .insert([
                        "receiver_id": offlineCheckIn.receiverId.uuidString,
                        "family_id": offlineCheckIn.familyId.uuidString,
                        "checked_in_at": ISO8601DateFormatter().string(from: offlineCheckIn.createdAt),
                        "mood": offlineCheckIn.mood ?? "",
                        "source": offlineCheckIn.source,
                    ])
                    .execute()

                offlineCheckIn.synced = true
                try context.save()
            } catch {
                print("Failed to sync offline check-in \(offlineCheckIn.id): \(error.localizedDescription)")
                break // Stop on first failure, retry later
            }
        }

        updatePendingCount()
    }

    // MARK: - Private

    private func setupModelContainer() {
        do {
            modelContainer = try ModelContainer(for: OfflineCheckIn.self)
        } catch {
            print("Failed to create SwiftData container: \(error.localizedDescription)")
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
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OfflineCheckIn>(
            predicate: #Predicate { !$0.synced }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
