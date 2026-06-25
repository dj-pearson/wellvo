import XCTest
@testable import DailyOK

/// Request/response coverage for the check-in path (US-IOS110). Two seams are
/// exercised: the pure request-body builder (numeric fields must serialize as
/// JSON numbers — US-IOS078) and a mockable `EdgeFunctionsClient` transport that
/// lets us drive a full invoke→decode round trip, proving the forgiving enum
/// decode (US-IOS087) survives an unrecognized server `source`/`response_type`.
final class CheckInServiceTests: XCTestCase {

    override func tearDown() {
        // Never leak the test transport into other tests / the real network path.
        EdgeFunctionsClient.testTransport = nil
        super.tearDown()
    }

    // MARK: - Request body (US-IOS078)

    func testCheckInBodySerializesNumericFieldsAsJSONNumbers() throws {
        let body = CheckInService.makeCheckInBody(
            receiverId: UUID(),
            familyId: UUID(),
            mood: .happy,
            source: .app,
            responseType: .ok,
            location: CheckInLocation(latitude: 37.7759, longitude: -122.4194, accuracy: 12.5),
            batteryLevel: 0.5,
            locationLabel: "home",
            kidResponseType: nil,
            slotKey: "08:00"
        )
        let json = String(data: try JSONEncoder().encode(body), encoding: .utf8)!
        // Numeric fields must be unquoted so the edge validators (typeof number) pass.
        XCTAssertTrue(json.contains("37.7759"))
        XCTAssertFalse(json.contains("\"37.7759\""))
        XCTAssertFalse(json.contains("\"-122.4194\""))
        XCTAssertFalse(json.contains("\"0.5\""))
        XCTAssertFalse(json.contains("\"12.5\""))
        // String fields stay quoted.
        XCTAssertTrue(json.contains("\"08:00\""))
        XCTAssertTrue(json.contains("\"happy\""))
    }

    func testCheckInBodyDropsOutOfRangeLocationAndBattery() throws {
        let body = CheckInService.makeCheckInBody(
            receiverId: UUID(),
            familyId: UUID(),
            mood: nil,
            source: .notification,
            responseType: .ok,
            location: CheckInLocation(latitude: 200, longitude: 400, accuracy: -1),
            batteryLevel: 5,            // out of 0...1
            locationLabel: nil,
            kidResponseType: nil,
            slotKey: nil
        )
        XCTAssertNil(body["latitude"])
        XCTAssertNil(body["longitude"])
        XCTAssertNil(body["battery_level"])
        XCTAssertNil(body["slot_key"])
        XCTAssertNil(body["mood"])
        // Required identity/response fields always present.
        XCTAssertNotNil(body["receiver_id"])
        XCTAssertEqual(body["source"]?.stringValue, "notification")
        XCTAssertEqual(body["response_type"]?.stringValue, "ok")
    }

    func testCheckInBodyDropsAccuracyWhenLocationValidButAccuracyOutOfRange() throws {
        let body = CheckInService.makeCheckInBody(
            receiverId: UUID(),
            familyId: UUID(),
            mood: nil,
            source: .app,
            responseType: .ok,
            location: CheckInLocation(latitude: 40, longitude: -73, accuracy: 999_999),
            batteryLevel: nil,
            locationLabel: nil,
            kidResponseType: nil,
            slotKey: nil
        )
        XCTAssertNotNil(body["latitude"])
        XCTAssertNotNil(body["longitude"])
        XCTAssertNil(body["location_accuracy_meters"]) // accuracy clamped out
    }

    // MARK: - Transport round trip (US-IOS087 forgiving decode)

    func testInvokeDecodesUnknownEnumsThroughMockTransport() async throws {
        let responseJSON = """
        {
          "success": true,
          "checkin": {
            "id": "\(UUID().uuidString)",
            "receiver_id": "\(UUID().uuidString)",
            "family_id": "\(UUID().uuidString)",
            "checked_in_at": "2026-06-10T08:00:00Z",
            "source": "some_future_surface",
            "response_type": "brand_new_type"
          }
        }
        """
        EdgeFunctionsClient.testTransport = { name, _ in
            XCTAssertEqual(name, "process-checkin-response")
            return Data(responseJSON.utf8)
        }

        let response: CheckInResponse = try await EdgeFunctionsClient.invoke(
            "process-checkin-response",
            json: ["receiver_id": .string("x")]
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.checkin.source, .app)          // unknown -> safe default
        XCTAssertEqual(response.checkin.responseType, .ok)     // unknown -> success
    }

    func testRespondToCheckInSendsNumericBodyThroughTransport() async throws {
        let recorder = BodyRecorder()
        EdgeFunctionsClient.testTransport = { _, httpBody in
            recorder.record(httpBody)
            return Data("{}".utf8)
        }

        try await CheckInService.shared.respondToCheckIn(
            requestId: "req-123",
            source: .notification,
            responseType: .ok,
            location: CheckInLocation(latitude: 37.42, longitude: -122.08, accuracy: 8),
            batteryLevel: 0.73
        )

        let json = String(data: try XCTUnwrap(recorder.body), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"req-123\""))
        XCTAssertTrue(json.contains("37.42"))
        XCTAssertFalse(json.contains("\"37.42\""))   // number, not string
        XCTAssertFalse(json.contains("\"0.73\""))
    }

    /// Thread-safe holder for the request body captured inside the `@Sendable`
    /// transport closure.
    private final class BodyRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        func record(_ data: Data?) { lock.lock(); stored = data; lock.unlock() }
        var body: Data? { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
