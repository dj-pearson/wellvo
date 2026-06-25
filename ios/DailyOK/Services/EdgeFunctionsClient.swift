import Foundation

/// HTTP client for the self-hosted edge-functions Deno server.
///
/// Replaces `supabase.functions.invoke(...)` which always targets
/// `<SUPABASE_URL>/functions/v1/...` (Supabase-hosted Edge Functions).
/// Our Deno server runs in a separate Coolify container reachable at
/// `Configuration.edgeFunctionsURL`.
/// A minimal JSON value for request bodies that must mix strings and numbers.
///
/// The edge-function validators require numeric fields (latitude, longitude,
/// battery_level, …) to arrive as real JSON numbers (`typeof === "number"`),
/// not quoted strings. A plain `[String: String]` body forced everything to a
/// string and every location-bearing check-in / report-location 400'd
/// (US-IOS078). Callers with numeric fields use the `json:` overloads and wrap
/// values explicitly, e.g. `["latitude": .double(lat), "family_id": .string(id)]`.
enum JSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

enum EdgeFunctionsClient {
    struct HTTPError: LocalizedError {
        let status: Int
        let body: String
        /// Seconds the server asked us to wait before retrying (parsed from the
        /// `Retry-After` header on 429/503), if present. Honored by NetworkRetry.
        let retryAfter: TimeInterval?

        init(status: Int, body: String, retryAfter: TimeInterval? = nil) {
            self.status = status
            self.body = body
            self.retryAfter = retryAfter
        }

        var errorDescription: String? {
            "Edge function error \(status): \(body)"
        }
    }

    /// 426 force-update payload from the server (see edge-functions/shared/config.ts).
    private struct ForceUpdateResponse: Decodable {
        let force_update: Bool?
        let min_version: String?
        let update_url: String?
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFractional.date(from: str) { return d }

            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: str) { return d }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(str)"
            )
        }
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Invoke an edge function and decode a typed response.
    static func invoke<T: Decodable>(
        _ name: String,
        body: [String: String]? = nil
    ) async throws -> T {
        let httpBody = try body.map { try encoder.encode($0) }
        let data = try await rawInvoke(name, httpBody: httpBody)
        return try decoder.decode(T.self, from: data)
    }

    /// Invoke an edge function, ignoring the response body.
    static func invoke(
        _ name: String,
        body: [String: String]? = nil
    ) async throws {
        let httpBody = try body.map { try encoder.encode($0) }
        _ = try await rawInvoke(name, httpBody: httpBody)
    }

    /// Invoke an edge function with a heterogeneous JSON body (numbers stay
    /// numbers). Use for location/battery payloads — see `JSONValue`.
    static func invoke<T: Decodable>(
        _ name: String,
        json: [String: JSONValue]
    ) async throws -> T {
        let data = try await rawInvoke(name, httpBody: try encoder.encode(json))
        return try decoder.decode(T.self, from: data)
    }

    /// Invoke an edge function with a heterogeneous JSON body, ignoring the response.
    static func invoke(
        _ name: String,
        json: [String: JSONValue]
    ) async throws {
        _ = try await rawInvoke(name, httpBody: try encoder.encode(json))
    }

    private static func rawInvoke(_ name: String, httpBody: Data?) async throws -> Data {
        guard let url = URL(string: "\(Configuration.edgeFunctionsURL)/\(name)") else {
            throw DailyOKError.unknown(NSError(domain: "EdgeFunctions", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        // Let the backend enforce MIN_SUPPORTED_IOS_APP_VERSION (force-update).
        request.setValue(Configuration.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue("ios", forHTTPHeaderField: "X-App-Platform")

        if let session = try? await SupabaseService.shared.client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = httpBody ?? Data("{}".utf8)

        let (data, response) = try await PinnedURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DailyOKError.unknown(NSError(domain: "EdgeFunctions", code: -2))
        }

        // 426 Upgrade Required: this build is below MIN_SUPPORTED_IOS_APP_VERSION.
        // Latch the global force-update state so the UI blocks with an update CTA.
        if http.statusCode == 426 {
            let updateURL = (try? decoder.decode(ForceUpdateResponse.self, from: data))?.update_url
            await ForceUpdateState.shared.trigger(updateURLString: updateURL)
            throw HTTPError(status: 426, body: "update_required")
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
            throw HTTPError(status: http.statusCode, body: bodyString, retryAfter: retryAfter)
        }

        return data
    }

    /// Parse a `Retry-After` header value. Supports the delta-seconds form
    /// (e.g. "120"); the HTTP-date form is uncommon for our API and is ignored.
    private static func parseRetryAfter(_ value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), let seconds = Double(value) else {
            return nil
        }
        return seconds >= 0 ? seconds : nil
    }
}
