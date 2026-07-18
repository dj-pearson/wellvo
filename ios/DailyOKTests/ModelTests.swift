import XCTest
@testable import DailyOK

/// Tests for model encoding/decoding and business logic
final class ModelTests: XCTestCase {

    // MARK: - CheckIn Model

    func testCheckInDecoding() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "receiver_id": "22222222-2222-2222-2222-222222222222",
            "family_id": "33333333-3333-3333-3333-333333333333",
            "checked_in_at": "2026-03-18T08:30:00Z",
            "mood": "happy",
            "source": "app",
            "scheduled_for": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let checkIn = try decoder.decode(CheckIn.self, from: json)

        XCTAssertEqual(checkIn.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(checkIn.mood, .happy)
        XCTAssertEqual(checkIn.source, .app)
        XCTAssertNil(checkIn.scheduledFor)
    }

    func testCheckInAllMoods() {
        XCTAssertEqual(Mood.allCases.count, 3)
        XCTAssertEqual(Mood.happy.rawValue, "happy")
        XCTAssertEqual(Mood.neutral.rawValue, "neutral")
        XCTAssertEqual(Mood.tired.rawValue, "tired")
    }

    func testCheckInSources() {
        XCTAssertEqual(CheckInSource.app.rawValue, "app")
        XCTAssertEqual(CheckInSource.notification.rawValue, "notification")
        XCTAssertEqual(CheckInSource.onDemand.rawValue, "on_demand")
    }

    // MARK: - Family Model

    func testFamilyDecoding() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "name": "Test Family",
            "owner_id": "55555555-5555-5555-5555-555555555555",
            "subscription_tier": "family",
            "subscription_status": "active",
            "subscription_expires_at": null,
            "max_receivers": 5,
            "max_viewers": 3,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let family = try decoder.decode(Family.self, from: json)

        XCTAssertEqual(family.name, "Test Family")
        XCTAssertEqual(family.subscriptionTier, .family)
        XCTAssertEqual(family.subscriptionStatus, .active)
        XCTAssertEqual(family.maxReceivers, 5)
    }

    func testSubscriptionTiers() {
        XCTAssertEqual(SubscriptionTier.free.rawValue, "free")
        XCTAssertEqual(SubscriptionTier.caregiver.rawValue, "caregiver")
        XCTAssertEqual(SubscriptionTier.family.rawValue, "family")
        XCTAssertEqual(SubscriptionTier.familyPlus.rawValue, "family_plus")
    }

    func testFamilyDecodingWithGrandfatherExpiry() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "name": "Legacy Free Family",
            "owner_id": "55555555-5555-5555-5555-555555555555",
            "subscription_tier": "free",
            "subscription_status": "active",
            "subscription_expires_at": null,
            "free_tier_expires_at": "2026-07-10T00:00:00Z",
            "max_receivers": 1,
            "max_viewers": 0,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let family = try decoder.decode(Family.self, from: json)

        XCTAssertEqual(family.subscriptionTier, .free)
        XCTAssertNotNil(family.freeTierExpiresAt)
    }

    func testFamilyDecodingCaregiver() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "name": "Caregiver Family",
            "owner_id": "55555555-5555-5555-5555-555555555555",
            "subscription_tier": "caregiver",
            "subscription_status": "active",
            "subscription_expires_at": null,
            "max_receivers": 1,
            "max_viewers": 3,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let family = try decoder.decode(Family.self, from: json)

        XCTAssertEqual(family.subscriptionTier, .caregiver)
        XCTAssertEqual(family.maxReceivers, 1)
        XCTAssertEqual(family.maxViewers, 3)
        XCTAssertNil(family.freeTierExpiresAt)
    }

    // MARK: - User Model

    func testAppUserDecoding() throws {
        let json = """
        {
            "id": "66666666-6666-6666-6666-666666666666",
            "email": "test@example.com",
            "phone": "+1234567890",
            "display_name": "Test User",
            "role": "owner",
            "avatar_url": null,
            "timezone": "America/New_York",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-03-18T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let user = try decoder.decode(AppUser.self, from: json)

        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertEqual(user.role, .owner)
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertNil(user.avatarUrl)
    }

    // MARK: - ReceiverSettings Model

    func testReceiverSettingsDecoding() throws {
        let json = """
        {
            "id": "77777777-7777-7777-7777-777777777777",
            "family_member_id": "88888888-8888-8888-8888-888888888888",
            "checkin_time": "08:00",
            "timezone": "America/Chicago",
            "grace_period_minutes": 30,
            "reminder_interval_minutes": 15,
            "escalation_enabled": true,
            "quiet_hours_start": "22:00",
            "quiet_hours_end": "07:00",
            "mood_tracking_enabled": true,
            "sms_escalation_enabled": false,
            "is_active": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let settings = try decoder.decode(ReceiverSettings.self, from: json)

        XCTAssertEqual(settings.checkinTime, "08:00")
        XCTAssertEqual(settings.gracePeriodMinutes, 30)
        XCTAssertTrue(settings.escalationEnabled)
        XCTAssertEqual(settings.quietHoursStart, "22:00")
        XCTAssertTrue(settings.moodTrackingEnabled)
        XCTAssertFalse(settings.smsEscalationEnabled)
    }

    // MARK: - SharedCheckInState day-scoped doneness (US-IOS113)

    private func makeSharedState(hasCheckedInToday: Bool, lastCheckInAt: Date?) -> SharedCheckInState {
        SharedCheckInState(
            receiverId: "r", familyId: "f", displayName: nil, isKidMode: false,
            supabaseURL: "https://x", anonKey: "k", edgeFunctionsURL: "https://e",
            hasCheckedInToday: hasCheckedInToday, lastCheckInAt: lastCheckInAt,
            nextCheckInAt: nil, updatedAt: Date()
        )
    }

    func testIsCheckedInTrueForSameDay() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000) // fixed instant
        let earlierToday = now.addingTimeInterval(-3 * 3600)
        let state = makeSharedState(hasCheckedInToday: true, lastCheckInAt: earlierToday)
        XCTAssertTrue(state.isCheckedIn(asOf: now, calendar: cal))
    }

    func testIsCheckedInFalseForPreviousDay() {
        // The flag is stale-true (never cleared at midnight), but the check-in
        // landed yesterday — a new day must re-enable the tap.
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let yesterday = now.addingTimeInterval(-26 * 3600)
        let state = makeSharedState(hasCheckedInToday: true, lastCheckInAt: yesterday)
        XCTAssertFalse(state.isCheckedIn(asOf: now, calendar: cal))
    }

    func testIsCheckedInFalseWhenNoLastCheckIn() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertFalse(makeSharedState(hasCheckedInToday: true, lastCheckInAt: nil).isCheckedIn(asOf: now, calendar: cal))
    }

    func testIsCheckedInRespectsFalseFlagEvenIfLastCheckInToday() {
        // Phone is authoritative: a false flag means not-done even if a stale
        // lastCheckInAt happens to fall today.
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let state = makeSharedState(hasCheckedInToday: false, lastCheckInAt: now)
        XCTAssertFalse(state.isCheckedIn(asOf: now, calendar: cal))
    }

    // MARK: - Snooze state (US-IOS114)

    private func makeRequest(snoozedUntil: Date?) -> CheckInRequest {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "family_id": UUID().uuidString,
            "receiver_id": UUID().uuidString,
            "requested_by": UUID().uuidString,
            "type": "scheduled",
            "status": "pending",
            "created_at": "2026-06-10T08:00:00Z",
            "escalation_step": 0,
        ]
        if let snoozedUntil {
            let f = ISO8601DateFormatter()
            dict["snoozed_until"] = f.string(from: snoozedUntil)
        }
        // swiftlint:disable:next force_try — fixture dict is a compile-time-known
        // literal; a failure here is a broken test, so crashing is correct.
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try — see above.
        return try! decoder.decode(CheckInRequest.self, from: data)
    }

    func testSnoozedRequestIsNotActivelyPending() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let req = makeRequest(snoozedUntil: now.addingTimeInterval(15 * 60))
        XCTAssertFalse(ReceiverViewModel.isActivelyPending(req, now: now))
    }

    func testElapsedSnoozeRequestIsActivelyPending() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let req = makeRequest(snoozedUntil: now.addingTimeInterval(-60))
        XCTAssertTrue(ReceiverViewModel.isActivelyPending(req, now: now))
    }

    func testUnsnoozedRequestIsActivelyPending() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertTrue(ReceiverViewModel.isActivelyPending(makeRequest(snoozedUntil: nil), now: now))
    }

    func testNilRequestIsNotActivelyPending() {
        XCTAssertFalse(ReceiverViewModel.isActivelyPending(nil))
    }

    // MARK: - Forgiving enum decode (backward compatibility)
    //
    // Persistent server enums must tolerate values a shipped build doesn't know
    // (per CLAUDE.md). A newer backend value must NOT throw the whole struct
    // decode — that previously took down the owner dashboard / receiver status.

    private func iso8601Decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testFamilyDecodesUnknownTierAndStatusWithoutThrowing() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Test Family",
            "owner_id": "22222222-2222-2222-2222-222222222222",
            "subscription_tier": "galaxy_ultra",
            "subscription_status": "paused",
            "max_receivers": 1,
            "max_viewers": 3,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let family = try iso8601Decoder().decode(Family.self, from: json)
        XCTAssertEqual(family.subscriptionTier, .free)
        XCTAssertEqual(family.subscriptionStatus, .active)
    }

    func testFamilyMemberDecodesUnknownRoleAndStatusWithoutThrowing() throws {
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "family_id": "44444444-4444-4444-4444-444444444444",
            "user_id": "55555555-5555-5555-5555-555555555555",
            "role": "superadmin",
            "status": "pending_review"
        }
        """.data(using: .utf8)!
        let member = try iso8601Decoder().decode(FamilyMember.self, from: json)
        XCTAssertEqual(member.role, .viewer)          // fail closed to least privilege
        XCTAssertEqual(member.status, .deactivated)   // treat unknown as not-active
    }

    func testAppUserDecodesNullTimezoneWithoutThrowing() throws {
        let json = """
        {
            "id": "66666666-6666-6666-6666-666666666666",
            "email": "test@example.com",
            "phone": null,
            "display_name": "Test User",
            "role": "receiver",
            "avatar_url": null,
            "timezone": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-03-18T00:00:00Z"
        }
        """.data(using: .utf8)!
        let user = try iso8601Decoder().decode(AppUser.self, from: json)
        XCTAssertNil(user.timezone)
        XCTAssertEqual(user.role, .receiver)
    }

    func testCheckInRequestDecodesUnknownStatusAsExpired() throws {
        let json = """
        {
            "id": "77777777-7777-7777-7777-777777777777",
            "family_id": "88888888-8888-8888-8888-888888888888",
            "receiver_id": "99999999-9999-9999-9999-999999999999",
            "requested_by": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "type": "recurring_beta",
            "status": "acknowledged",
            "created_at": "2026-06-10T08:00:00Z",
            "escalation_step": 0
        }
        """.data(using: .utf8)!
        let req = try iso8601Decoder().decode(CheckInRequest.self, from: json)
        XCTAssertEqual(req.status, .expired)   // never a phantom .pending escalation
        XCTAssertEqual(req.type, .scheduled)
    }

    func testReceiverSettingsDecodesUnknownScheduleTypeAsDaily() throws {
        let json = """
        {
            "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "family_member_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
            "checkin_time": "08:00",
            "timezone": "America/Chicago",
            "grace_period_minutes": 30,
            "reminder_interval_minutes": 15,
            "escalation_enabled": true,
            "quiet_hours_start": "22:00",
            "quiet_hours_end": "07:00",
            "mood_tracking_enabled": true,
            "sms_escalation_enabled": false,
            "is_active": true,
            "schedule_type": "biweekly"
        }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ReceiverSettings.self, from: json)
        XCTAssertEqual(settings.scheduleType, .daily)
    }
}
