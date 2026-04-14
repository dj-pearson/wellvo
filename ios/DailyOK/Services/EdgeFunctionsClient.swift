import Foundation

/// HTTP client for the self-hosted edge-functions Deno server.
///
/// Replaces `supabase.functions.invoke(...)` which always targets
/// `<SUPABASE_URL>/functions/v1/...` (Supabase-hosted Edge Functions).
/// Our Deno server runs in a separate Coolify container reachable at
/// `Configuration.edgeFunctionsURL`.
enum EdgeFunctionsClient {
    struct HTTPError: LocalizedError {
        let status: Int
        let body: String
        var errorDescription: String? {
            "Edge function error \(status): \(body)"
        }
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
        let data = try await rawInvoke(name, body: body)
        return try decoder.decode(T.self, from: data)
    }

    /// Invoke an edge function, ignoring the response body.
    static func invoke(
        _ name: String,
        body: [String: String]? = nil
    ) async throws {
        _ = try await rawInvoke(name, body: body)
    }

    private static func rawInvoke(_ name: String, body: [String: String]?) async throws -> Data {
        guard let url = URL(string: "\(Configuration.edgeFunctionsURL)/\(name)") else {
            throw DailyOKError.unknown(NSError(domain: "EdgeFunctions", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let session = try? await SupabaseService.shared.client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DailyOKError.unknown(NSError(domain: "EdgeFunctions", code: -2))
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw HTTPError(status: http.statusCode, body: bodyString)
        }

        return data
    }
}
