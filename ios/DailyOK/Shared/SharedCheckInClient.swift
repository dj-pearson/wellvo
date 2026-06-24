import Foundation

enum SharedCheckInError: LocalizedError {
    case notSignedIn
    case sessionExpired
    case badConfiguration
    case server(Int, String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Open Daily OK on your iPhone and sign in first."
        case .sessionExpired:
            return "Your session expired. Open Daily OK on your iPhone to sign back in."
        case .badConfiguration:
            return "Daily OK isn't set up yet. Open the app once to finish setup."
        case .server(let code, _):
            return "The check-in didn't go through (error \(code)). Please try again."
        case .transport:
            return "Couldn't reach Daily OK. Check your connection and try again."
        }
    }
}

/// Performs an "I'm OK" check-in using only the shared App Group snapshot — no
/// Supabase SDK dependency — so it can run from App Intents, widgets, the
/// Control Center control, and the watch. Hits the same
/// `process-checkin-response` edge function the in-app path uses, so there is no
/// new backend contract.
enum SharedCheckInClient {
    /// Perform a check-in and return the updated snapshot.
    /// - Parameters:
    ///   - responseType: `ok` / `need_help` / `call_me`.
    ///   - source: how the check-in was initiated (e.g. `app`, `widget`, `watch`).
    ///   - batteryLevel: 0...1 if the calling surface can supply it.
    @discardableResult
    static func checkIn(
        responseType: String = "ok",
        source: String = "app",
        batteryLevel: Double? = nil
    ) async throws -> SharedCheckInState {
        guard var state = SharedCheckInStore.load() else { throw SharedCheckInError.notSignedIn }
        // The session secrets live in the Keychain, not the snapshot plist. No
        // tokens means signed-out, or biometric lock has withheld them — either
        // way this surface must not act.
        guard var tokens = SharedKeychain.loadTokens() else { throw SharedCheckInError.notSignedIn }

        if tokens.isAccessTokenExpired {
            tokens = try await refreshSession(state, tokens: tokens)
        }

        var body: [String: String] = [
            "receiver_id": state.receiverId,
            "family_id": state.familyId,
            "source": source,
            "response_type": responseType,
        ]
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = String(battery)
        }

        do {
            try await postCheckIn(state: state, accessToken: tokens.accessToken, body: body)
        } catch SharedCheckInError.server(let code, _) where code == 401 {
            // Token may have expired between the check and the request — refresh
            // once and retry so a wrist/widget tap isn't lost (which would leave
            // the request pending and falsely escalate to the owner).
            tokens = try await refreshSession(state, tokens: tokens)
            try await postCheckIn(state: state, accessToken: tokens.accessToken, body: body)
        }

        state.hasCheckedInToday = true
        state.lastCheckInAt = Date()
        state.updatedAt = Date()
        SharedCheckInStore.save(state)
        return state
    }

    // MARK: - Networking

    private static func postCheckIn(state: SharedCheckInState, accessToken: String, body: [String: String]) async throws {
        guard let url = URL(string: "\(state.edgeFunctionsURL)/process-checkin-response") else {
            throw SharedCheckInError.badConfiguration
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(state.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await PinnedURLSession.shared.data(for: req)
        } catch {
            throw SharedCheckInError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SharedCheckInError.server(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SharedCheckInError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Refresh the Supabase access token using the refresh token and persist the
    /// rotated tokens back to the shared Keychain.
    private static func refreshSession(_ state: SharedCheckInState, tokens: SharedAuthTokens) async throws -> SharedAuthTokens {
        guard let url = URL(string: "\(state.supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            throw SharedCheckInError.sessionExpired
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(state.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": tokens.refreshToken])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await PinnedURLSession.shared.data(for: req)
        } catch {
            throw SharedCheckInError.transport(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SharedCheckInError.sessionExpired
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw SharedCheckInError.sessionExpired
        }

        let updated = SharedAuthTokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in))
        )
        SharedKeychain.saveTokens(updated)
        return updated
    }
}
