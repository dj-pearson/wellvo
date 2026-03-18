import Foundation
import Supabase

actor CheckInService {
    static let shared = CheckInService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    /// Receiver performs a check-in
    func checkIn(familyId: UUID, mood: Mood? = nil, source: CheckInSource = .app) async throws -> CheckIn {
        guard let session = try? await supabase.auth.session else {
            throw CheckInError.notAuthenticated
        }

        let checkIn: CheckIn = try await supabase
            .from("checkins")
            .insert([
                "receiver_id": session.user.id.uuidString,
                "family_id": familyId.uuidString,
                "checked_in_at": ISO8601DateFormatter().string(from: Date()),
                "mood": mood?.rawValue ?? "",
                "source": source.rawValue,
            ])
            .select()
            .single()
            .execute()
            .value

        // Also update any pending check-in requests
        try await supabase.functions.invoke(
            "process-checkin-response",
            options: .init(body: [
                "receiver_id": session.user.id.uuidString,
                "family_id": familyId.uuidString,
            ])
        )

        return checkIn
    }

    /// Respond to a specific check-in request (from notification)
    func respondToCheckIn(requestId: String, source: CheckInSource = .notification) async {
        do {
            try await supabase.functions.invoke(
                "process-checkin-response",
                options: .init(body: [
                    "checkin_request_id": requestId,
                    "source": source.rawValue,
                ])
            )
        } catch {
            print("Failed to respond to check-in: \(error.localizedDescription)")
        }
    }

    /// Owner sends on-demand check-in request
    func sendOnDemandCheckIn(receiverId: UUID, familyId: UUID) async throws {
        try await supabase.functions.invoke(
            "on-demand-checkin",
            options: .init(body: [
                "receiver_id": receiverId.uuidString,
                "family_id": familyId.uuidString,
            ])
        )
    }

    /// Fetch today's check-in status for a receiver
    func todayCheckInStatus(receiverId: UUID, familyId: UUID) async throws -> CheckIn? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()

        let checkIns: [CheckIn] = try await supabase
            .from("checkins")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .gte("checked_in_at", value: formatter.string(from: startOfDay))
            .order("checked_in_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return checkIns.first
    }

    /// Fetch check-in history for a receiver
    func checkInHistory(receiverId: UUID, familyId: UUID, days: Int = 30) async throws -> [CheckIn] {
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let formatter = ISO8601DateFormatter()

        let checkIns: [CheckIn] = try await supabase
            .from("checkins")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .gte("checked_in_at", value: formatter.string(from: fromDate))
            .order("checked_in_at", ascending: false)
            .execute()
            .value

        return checkIns
    }
}

enum CheckInError: LocalizedError {
    case notAuthenticated
    case alreadyCheckedIn

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to check in"
        case .alreadyCheckedIn: return "You've already checked in today"
        }
    }
}
