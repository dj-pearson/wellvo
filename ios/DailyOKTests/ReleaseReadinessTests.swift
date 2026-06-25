import XCTest
@testable import DailyOK

/// Unit coverage for the safety-critical encode/decode/retry paths hardened in
/// the iOS release-readiness pass (US-IOS110). These are pure and runnable
/// without a device, StoreKit, or the network.
final class ReleaseReadinessTests: XCTestCase {

    private func isoDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - US-IOS078: numeric request fields serialize as JSON numbers

    func testJSONValueSerializesNumbersUnquoted() throws {
        let body: [String: JSONValue] = [
            "latitude": .double(37.7759),
            "battery_level": .double(0.5),
            "family_id": .string("abc-123"),
        ]
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8)!
        // Numbers must NOT be quoted (the server validators require typeof number).
        XCTAssertTrue(json.contains("37.7759"))
        XCTAssertFalse(json.contains("\"37.7759\""))
        XCTAssertFalse(json.contains("\"0.5\""))
        // Strings stay quoted.
        XCTAssertTrue(json.contains("\"abc-123\""))
    }

    func testJSONValueDoubleValueParsesAllForms() {
        XCTAssertEqual(JSONValue.int(3).doubleValue, 3)
        XCTAssertEqual(JSONValue.double(2.5).doubleValue, 2.5)
        XCTAssertEqual(JSONValue.string("4.5").doubleValue, 4.5)
        XCTAssertNil(JSONValue.string("nope").doubleValue)
        XCTAssertNil(JSONValue.bool(true).doubleValue)
    }

    // MARK: - US-IOS087: forgiving CheckIn enum decoding

    func testCheckInDecodesUnknownSourceAndResponseTypeWithoutThrowing() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "receiver_id": "\(UUID().uuidString)",
          "family_id": "\(UUID().uuidString)",
          "checked_in_at": "2026-06-10T08:00:00Z",
          "source": "some_future_surface",
          "response_type": "brand_new_type"
        }
        """.data(using: .utf8)!
        let checkIn = try isoDecoder().decode(CheckIn.self, from: json)
        XCTAssertEqual(checkIn.source, .app)            // unknown -> safe default
        XCTAssertEqual(checkIn.responseType, .ok)       // unknown -> success, not failure
    }

    func testCheckInDecodesKnownNewSurfaceSources() throws {
        for raw in ["widget", "control", "siri"] {
            let json = """
            {"id":"\(UUID().uuidString)","receiver_id":"\(UUID().uuidString)",
             "family_id":"\(UUID().uuidString)","checked_in_at":"2026-06-10T08:00:00Z",
             "source":"\(raw)"}
            """.data(using: .utf8)!
            let checkIn = try isoDecoder().decode(CheckIn.self, from: json)
            XCTAssertEqual(checkIn.source.rawValue, raw)
        }
    }

    // MARK: - US-IOS101: Mood unknown decode

    func testMoodDecodesUnknownToUnknownNotNeutral() throws {
        let value = try JSONDecoder().decode(Mood.self, from: "\"telepathic\"".data(using: .utf8)!)
        XCTAssertEqual(value, .unknown)
        let known = try JSONDecoder().decode(Mood.self, from: "\"happy\"".data(using: .utf8)!)
        XCTAssertEqual(known, .happy)
    }

    // MARK: - US-IOS079: forgiving DailyOKAlert.data decoding

    func testAlertDecodesHeterogeneousDataWithStringAndNumber() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "family_id": "\(UUID().uuidString)",
          "receiver_id": "\(UUID().uuidString)",
          "type": "low_battery",
          "title": "Low battery",
          "message": "Phone battery is low",
          "is_read": false,
          "created_at": "2026-06-10T08:00:00Z",
          "data": { "battery_level": 0.12, "last_seen_at": "2026-06-10T07:55:00Z" }
        }
        """.data(using: .utf8)!
        let alert = try isoDecoder().decode(DailyOKAlert.self, from: json)
        XCTAssertEqual(alert.data?["battery_level"]?.doubleValue, 0.12)
        XCTAssertEqual(alert.data?["last_seen_at"]?.stringValue, "2026-06-10T07:55:00Z")
    }

    func testAlertArrayDecodeSurvivesOneMalformedDataPayload() throws {
        // One alert with a non-object `data` must not blank the whole array.
        let id1 = UUID().uuidString, id2 = UUID().uuidString
        let fam = UUID().uuidString, rec = UUID().uuidString
        let json = """
        [
          {"id":"\(id1)","family_id":"\(fam)","receiver_id":"\(rec)","type":"low_battery",
           "title":"A","message":"a","is_read":false,"created_at":"2026-06-10T08:00:00Z",
           "data": 42},
          {"id":"\(id2)","family_id":"\(fam)","receiver_id":"\(rec)","type":"time_drift",
           "title":"B","message":"b","is_read":false,"created_at":"2026-06-10T08:00:00Z",
           "data": {"drift_hours": 2.0}}
        ]
        """.data(using: .utf8)!
        let alerts = try isoDecoder().decode([DailyOKAlert].self, from: json)
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts[1].data?["drift_hours"]?.doubleValue, 2.0)
    }

    // MARK: - US-IOS088: retry classification

    func testHTTP4xxIsNonRetryableExcept408And429() {
        XCTAssertTrue(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 400, body: "")))
        XCTAssertTrue(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 403, body: "")))
        XCTAssertTrue(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 404, body: "")))
        XCTAssertFalse(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 408, body: "")))
        XCTAssertFalse(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 429, body: "")))
        // 5xx are transient -> retryable.
        XCTAssertFalse(NetworkRetry.isNonRetryable(EdgeFunctionsClient.HTTPError(status: 503, body: "")))
    }

    func testCancelledURLErrorIsNonRetryable() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertTrue(NetworkRetry.isNonRetryable(err))
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertFalse(NetworkRetry.isNonRetryable(timeout))
    }

    // MARK: - US-IOS097: free-tier grandfather expiry

    private func makeFamily(tier: String, freeTierExpiresAt: String?) throws -> Family {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Fam",
            "owner_id": UUID().uuidString,
            "subscription_tier": tier,
            "subscription_status": "active",
            "max_receivers": 1,
            "max_viewers": 3,
            "created_at": "2026-01-01T00:00:00Z",
        ]
        if let freeTierExpiresAt { dict["free_tier_expires_at"] = freeTierExpiresAt }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try isoDecoder().decode(Family.self, from: data)
    }

    func testFreeTierExpiredWhenDeadlinePast() throws {
        let f = try makeFamily(tier: "free", freeTierExpiresAt: "2020-01-01T00:00:00Z")
        XCTAssertTrue(f.isFreeTierExpired)
    }

    func testFreeTierNotExpiredWhenDeadlineFutureOrPaidTier() throws {
        let future = try makeFamily(tier: "free", freeTierExpiresAt: "2099-01-01T00:00:00Z")
        XCTAssertFalse(future.isFreeTierExpired)
        let paid = try makeFamily(tier: "caregiver", freeTierExpiresAt: "2020-01-01T00:00:00Z")
        XCTAssertFalse(paid.isFreeTierExpired)
        let noDeadline = try makeFamily(tier: "free", freeTierExpiresAt: nil)
        XCTAssertFalse(noDeadline.isFreeTierExpired)
    }
}
