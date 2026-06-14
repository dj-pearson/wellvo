import Foundation
import Supabase
import os

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
        batteryLevel: Double? = nil,
        locationLabel: String? = nil,
        kidResponseType: String? = nil
    ) async throws -> CheckIn {
        guard let session = try? await supabase.auth.session else {
            throw CheckInError.notAuthenticated
        }

        var body: [String: String] = [
            "receiver_id": session.user.id.uuidString.lowercased(),
            "family_id": familyId.uuidString.lowercased(),
            "source": source.rawValue,
            "response_type": responseType.rawValue,
        ]

        if let mood = mood { body["mood"] = mood.rawValue }
        if let loc = location {
            // Validate location bounds before sending
            if loc.latitude >= -90 && loc.latitude <= 90 &&
               loc.longitude >= -180 && loc.longitude <= 180 {
                body["latitude"] = String(loc.latitude)
                body["longitude"] = String(loc.longitude)
                if let accuracy = loc.accuracy, accuracy >= 0, accuracy <= 100000 {
                    body["location_accuracy_meters"] = String(accuracy)
                }
            }
        }
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = String(battery)
        }
        if let locationLabel {
            body["location_label"] = locationLabel
        }
        if let kidResponseType {
            body["kid_response_type"] = kidResponseType
        }

        // Use the edge function which handles location, response type, and alerts
        let result: CheckInResponse = try await EdgeFunctionsClient.invoke(
            "process-checkin-response",
            body: body
        )
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

            // Retry transient failures with backoff — a tapped "I'm OK" from the
            // lock screen on flaky signal shouldn't be silently lost (which would
            // leave the request pending and falsely escalate to the owner).
            try await NetworkRetry.execute {
                try await EdgeFunctionsClient.invoke(
                    "process-checkin-response",
                    body: body
                )
            }
        } catch {
            throw DailyOKError.network(error)
        }
    }

    /// Owner "stand down" — stop the escalation chain for a receiver's pending
    /// request(s) after reaching them another way (call, in person).
    func cancelEscalation(receiverId: UUID, familyId: UUID) async throws {
        try await EdgeFunctionsClient.invoke(
            "cancel-escalation",
            body: [
                "receiver_id": receiverId.uuidString,
                "family_id": familyId.uuidString,
            ]
        )
    }

    /// Confirm delivery of a push notification
    func confirmDelivery(checkinRequestId: String) async {
        // Part of the escalation-suppression contract: the server uses this to
        // know the push landed. A silently-dropped failure can let an escalation
        // fire unnecessarily, so retry transient failures and log if it sticks.
        do {
            try await NetworkRetry.execute {
                try await EdgeFunctionsClient.invoke(
                    "confirm-delivery",
                    body: ["checkin_request_id": checkinRequestId]
                )
            }
        } catch {
            Log.checkIn.error("confirmDelivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Owner sends on-demand check-in request
    func sendOnDemandCheckIn(receiverId: UUID, familyId: UUID) async throws {
        try await EdgeFunctionsClient.invoke(
            "on-demand-checkin",
            body: [
                "receiver_id": receiverId.uuidString,
                "family_id": familyId.uuidString,
            ]
        )
    }

    /// Fetch today's check-in status for a receiver.
    /// `timezone` is the receiver's IANA zone (from `users.timezone`). "Today"
    /// must be evaluated in the receiver's zone — not the viewer's device zone
    /// — otherwise an owner in a different region sees Pending even after the
    /// receiver tapped I'm OK.
    func todayCheckInStatus(receiverId: UUID, familyId: UUID, timezone: String? = nil) async throws -> CheckIn? {
        var calendar = Calendar.current
        if let tzId = timezone, let tz = TimeZone(identifier: tzId) {
            calendar.timeZone = tz
        }
        let startOfDay = calendar.startOfDay(for: Date())
        // Upper bound = start of tomorrow in the same timezone. Without this,
        // a row with a future `checked_in_at` (e.g. server-side clock skew, or
        // a legacy seed row) would satisfy the `gte` filter and be returned
        // as "today's check-in" even when the receiver hasn't actually
        // checked in.
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let formatter = ISO8601DateFormatter()
        let startISO = formatter.string(from: startOfDay)
        let endISO = formatter.string(from: startOfTomorrow)

        let checkIns: [CheckIn] = try await supabase
            .from("checkins")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .gte("checked_in_at", value: startISO)
            .lt("checked_in_at", value: endISO)
            .order("checked_in_at", ascending: false)
            .limit(1)
            .execute()
            .value

        // Defensive client-side verification: even if the server returned a
        // row, trust it only if its timestamp genuinely falls within today's
        // local-day window. This catches decoding quirks, stray rows with
        // wall-clock drift, and stale values the view model might still hold
        // onto from a previous sign-in.
        guard let candidate = checkIns.first else { return nil }
        if candidate.checkedInAt < startOfDay || candidate.checkedInAt >= startOfTomorrow {
            Log.checkIn.debug("Discarding out-of-window check-in candidate")
            return nil
        }
        return candidate
    }

    /// Fetch check-in history for a receiver
    func checkInHistory(receiverId: UUID, familyId: UUID, days: Int = 30) async throws -> [CheckIn] {
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date().addingTimeInterval(-Double(days) * 86_400)
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
