import SwiftUI
import Supabase

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published var hasCheckedInToday = false
    @Published var isCheckingIn = false
    @Published var lastCheckIn: CheckIn?
    @Published var errorMessage: String?
    @Published var familyId: UUID?
    @Published var isOffline = false
    @Published var pendingOfflineCount = 0
    @Published var receiverMode: ReceiverMode = .standard
    @Published var nextCheckInTime: Date?
    @Published var receiverSettings: ReceiverSettings?

    private let offlineService = OfflineCheckInService.shared

    func loadStatus() async {
        guard let family = try? await FamilyService.shared.getFamily() else { return }
        familyId = family.id

        guard let session = try? await SupabaseService.shared.client.auth.session else { return }

        struct TimezoneOnly: Decodable { let timezone: String? }
        let tzRow: TimezoneOnly? = try? await SupabaseService.shared.client
            .from("users")
            .select("timezone")
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value

        // Sync any queued offline check-ins first so the subsequent status
        // query reflects them. Without this, a synced check-in would only
        // appear after the next manual refresh.
        await offlineService.syncPendingCheckIns()

        // Reset state BEFORE the query so a stale `true` from yesterday
        // doesn't bleed into today if the query returns nil. The `@StateObject`
        // persists across scene phases, so without this reset the receiver
        // sees "you're all set" indefinitely once they check in once.
        let todayCheckIn = try? await CheckInService.shared.todayCheckInStatus(
            receiverId: session.user.id,
            familyId: family.id,
            timezone: tzRow?.timezone
        )
        #if DEBUG
        print("[ReceiverViewModel] loadStatus: tz=\(tzRow?.timezone ?? "nil") todayCheckIn=\(todayCheckIn?.checkedInAt.description ?? "nil")")
        #endif
        lastCheckIn = todayCheckIn
        hasCheckedInToday = (todayCheckIn != nil)

        await loadReceiverSettings(userId: session.user.id, familyId: family.id)

        isOffline = !offlineService.isOnline
        pendingOfflineCount = offlineService.pendingCount
    }

    private func loadReceiverSettings(userId: UUID, familyId: UUID) async {
        do {
            let members: [FamilyMember] = try await SupabaseService.shared.client
                .from("family_members")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("family_id", value: familyId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let member = members.first else { return }

            let settings: ReceiverSettings = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .single()
                .execute()
                .value

            receiverSettings = settings
            receiverMode = settings.receiverMode
            computeNextCheckInTime(from: settings)
        } catch {
            // Non-critical — default to standard mode
        }
    }

    private func computeNextCheckInTime(from settings: ReceiverSettings) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = String(settings.checkinTime.prefix(5))
        guard let parsedTime = formatter.date(from: timeString) else { return }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
        var tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        tomorrow = calendar.date(bySettingHour: timeComponents.hour ?? 9,
                                  minute: timeComponents.minute ?? 0,
                                  second: 0,
                                  of: tomorrow) ?? tomorrow
        nextCheckInTime = tomorrow
    }

    func performCheckIn() async {
        guard let familyId, !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil

        do {
            let checkIn = try await offlineService.performCheckIn(
                familyId: familyId,
                mood: nil,
                source: .app
            )

            if let checkIn {
                lastCheckIn = checkIn
            }
            hasCheckedInToday = true
            Task { await AnalyticsService.shared.track(.checkIn) }
        } catch let error as NetworkError {
            // Offline path: the check-in is queued locally and will sync when
            // connectivity returns. Show the success state optimistically.
            hasCheckedInToday = true
            isOffline = true
            Task { await AnalyticsService.shared.track(.checkInOffline) }
            pendingOfflineCount = offlineService.pendingCount
            errorMessage = error.localizedDescription
        } catch {
            // Real failure (auth, server 5xx, etc): do NOT flip the UI to
            // "checked in" — otherwise the receiver sees "you're all set"
            // for a check-in that was never recorded.
            errorMessage = error.localizedDescription
        }

        isCheckingIn = false
    }
}
