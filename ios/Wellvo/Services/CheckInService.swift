import Foundation
import Supabase

actor CheckInService {
    static let shared = CheckInService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    /// Receiver performs a check-in with optional response type and location
    func checkIn(
        familyId: UUID,
        mood: Mood? = nil,
        source: CheckInSource = .app,
        responseType: CheckInResponseType = .ok,
        location: CheckInLocation? = nil,
        batteryLevel: Double? = nil
    ) async throws -> CheckIn {
        guard let session = try? await supabase.auth.session else {
            throw CheckInError.notAuthenticated
        }

        var body: [String: String] = [
            "receiver_id": session.user.id.uuidString,
            "family_id": familyId.uuidString,
            "source": source.rawValue,
            "response_type": responseType.rawValue,
        ]

        if let mood = mood { body["mood"] = mood.rawValue }
        if let loc = location {
            body["latitude"] = String(loc.latitude)
            body["longitude"] = String(loc.longitude)
            if let accuracy = loc.accuracy {
                body["location_accuracy_meters"] = String(accuracy)
            }
        }
        if let battery = batteryLevel {
            body["battery_level"] = String(battery)
        }

        // Use the edge function which handles location, response type, and alerts
        let response = try await supabase.functions.invoke(
            "process-checkin-response",
            options: .init(body: body)
        )

        // Decode the check-in from the response
        let result = try JSONDecoder().decode(CheckInResponse.self, from: response.data)
        return result.checkin
    }

    /// Respond to a specific check-in request (from notification)
    func respondToCheckIn(
        requestId: String,
        source: CheckInSource = .notification,
        responseType: CheckInResponseType = .ok,
        location: CheckInLocation? = nil,
        batteryLevel: Double? = nil
    ) async throws {
        do {
            var body: [String: String] = [
                "checkin_request_id": requestId,
                "source": source.rawValue,
                "response_type": responseType.rawValue,
            ]
            if let loc = location {
                body["latitude"] = String(loc.latitude)
                body["longitude"] = String(loc.longitude)
                if let accuracy = loc.accuracy {
                    body["location_accuracy_meters"] = String(accuracy)
                }
            }
            if let battery = batteryLevel {
                body["battery_level"] = String(battery)
            }

            try await supabase.functions.invoke(
                "process-checkin-response",
                options: .init(body: body)
            )
        } catch {
            throw WellvoError.network(error)
        }
    }

    /// Confirm delivery of a push notification
    func confirmDelivery(checkinRequestId: String) async {
        try? await supabase.functions.invoke(
            "confirm-delivery",
            options: .init(body: [
                "checkin_request_id": checkinRequestId,
            ])
        )
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

struct CheckInLocation {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
}

private struct CheckInResponse: Codable {
    let success: Bool
    let checkin: CheckIn
}
