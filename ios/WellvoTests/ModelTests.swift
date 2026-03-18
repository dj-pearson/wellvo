import XCTest
@testable import Wellvo

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
        XCTAssertEqual(SubscriptionTier.family.rawValue, "family")
        XCTAssertEqual(SubscriptionTier.familyPlus.rawValue, "family_plus")
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
}
