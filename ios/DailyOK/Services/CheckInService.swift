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
        kidResponseType: String? = nil,
        slotKey: String? = nil
    ) async throws -> CheckIn {
        guard let session = try? await supabase.auth.session else {
            throw CheckInError.notAuthenticated
        }

        let body = Self.makeCheckInBody(
            receiverId: session.user.id,
            familyId: familyId,
            mood: mood,
            source: source,
            responseType: responseType,
            location: location,
            batteryLevel: batteryLevel,
            locationLabel: locationLabel,
            kidResponseType: kidResponseType,
            slotKey: slotKey
        )

        // Use the edge function which handles location, response type, and alerts
        let result: CheckInResponse = try await EdgeFunctionsClient.invoke(
            "process-checkin-response",
            json: body
        )
        return result.checkin
    }

    /// Build the `process-checkin-response` request body. Extracted as a pure
    /// function so the wire encoding — numeric fields as JSON numbers (US-IOS078),
    /// out-of-range location/battery dropped, optional slot/mood/label inclusion
    /// — is unit-testable without a live session or network (US-IOS110).
    static func makeCheckInBody(
        receiverId: UUID,
        familyId: UUID,
        mood: Mood?,
        source: CheckInSource,
        responseType: CheckInResponseType,
        location: CheckInLocation?,
        batteryLevel: Double?,
        locationLabel: String?,
        kidResponseType: String?,
        slotKey: String?
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "receiver_id": .string(receiverId.uuidString.lowercased()),
            "family_id": .string(familyId.uuidString.lowercased()),
            "source": .string(source.rawValue),
            "response_type": .string(responseType.rawValue),
        ]

        // US-IOS048: which scheduled window this check-in satisfies. Absent for
        // single-window receivers (preserves legacy one-per-day dedup).
        if let slotKey { body["slot_key"] = .string(slotKey) }
        if let mood = mood { body["mood"] = .string(mood.rawValue) }
        if let loc = location {
            // Validate location bounds before sending. Numeric fields go on the
            // wire as JSON numbers (US-IOS078) — the server validators require
            // typeof === "number".
            if loc.latitude >= -90 && loc.latitude <= 90 &&
               loc.longitude >= -180 && loc.longitude <= 180 {
                body["latitude"] = .double(loc.latitude)
                body["longitude"] = .double(loc.longitude)
                if let accuracy = loc.accuracy, accuracy >= 0, accuracy <= 100000 {
                    body["location_accuracy_meters"] = .double(accuracy)
                }
            }
        }
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = .double(battery)
        }
        if let locationLabel {
            body["location_label"] = .string(locationLabel)
        }
        if let kidResponseType {
            body["kid_response_type"] = .string(kidResponseType)
        }
        return body
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
            var body: [String: JSONValue] = [
                "checkin_request_id": .string(requestId),
                "source": .string(source.rawValue),
                "response_type": .string(responseType.rawValue),
            ]
            if let loc = location {
                body["latitude"] = .double(loc.latitude)
                body["longitude"] = .double(loc.longitude)
                if let accuracy = loc.accuracy {
                    body["location_accuracy_meters"] = .double(accuracy)
                }
            }
            if let battery = batteryLevel {
                body["battery_level"] = .double(battery)
            }

            // Retry transient failures with backoff — a tapped "I'm OK" from the
            // lock screen on flaky signal shouldn't be silently lost (which would
            // leave the request pending and falsely escalate to the owner).
            try await NetworkRetry.execute {
                try await EdgeFunctionsClient.invoke(
                    "process-checkin-response",
                    json: body
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

    /// Undo the receiver's most recent check-in within the server grace window
    /// (US-IOS048). Reverses the check-in row, deletes any alert it created, and
    /// re-opens the requests it closed. Throws if the grace window has lapsed.
    func undoLastCheckIn(familyId: UUID) async throws {
        guard let session = try? await supabase.auth.session else {
            throw CheckInError.notAuthenticated
        }
        try await EdgeFunctionsClient.invoke(
            "undo-checkin",
            body: [
                "receiver_id": session.user.id.uuidString.lowercased(),
                "family_id": familyId.uuidString.lowercased(),
            ]
        )
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

    private struct SnoozeParams: Encodable {
        let p_request_id: String
        let p_minutes: Int
    }

    /// Receiver snoozes their own pending request, deferring escalation by
    /// `minutes`. Bounded server-side (max 3 snoozes); throws if the limit is
    /// reached or the request is no longer pending. Returns the updated request
    /// so callers can read the new `snoozeCount` / `snoozedUntil`.
    @discardableResult
    func snoozeCheckIn(requestId: UUID, minutes: Int = 15) async throws -> CheckInRequest {
        try await supabase
            .rpc("snooze_checkin_request",
                 params: SnoozeParams(p_request_id: requestId.uuidString, p_minutes: minutes))
            .single()
            .execute()
            .value
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

    /// Fetch check-in history for a receiver over the last `days` days.
    func checkInHistory(receiverId: UUID, familyId: UUID, days: Int = 30) async throws -> [CheckIn] {
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date().addingTimeInterval(-Double(days) * 86_400)
        return try await checkInHistory(receiverId: receiverId, familyId: familyId, from: fromDate, to: nil)
    }

    /// Fetch check-in history for an explicit date range (for a caregiver report
    /// covering a custom window, e.g. ahead of a doctor visit). `to` defaults to
    /// now.
    func checkInHistory(receiverId: UUID, familyId: UUID, from: Date, to: Date? = nil) async throws -> [CheckIn] {
        let formatter = ISO8601DateFormatter()
        var query = supabase
            .from("checkins")
            .select()
            .eq("receiver_id", value: receiverId.uuidString)
            .eq("family_id", value: familyId.uuidString)
            .gte("checked_in_at", value: formatter.string(from: from))
        if let to {
            query = query.lt("checked_in_at", value: formatter.string(from: to))
        }
        let checkIns: [CheckIn] = try await query
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

// Internal (not private) so the round-trip decode through the test transport is
// exercisable from the unit tests (US-IOS110).
struct CheckInResponse: Codable {
    let success: Bool
    let checkin: CheckIn
}
