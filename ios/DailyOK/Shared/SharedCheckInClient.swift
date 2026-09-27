import Foundation

enum SharedCheckInError: LocalizedError {
    case notSignedIn
    case locked
    case sessionExpired
    case badConfiguration
    /// 403: the server no longer counts this person as an active receiver of
    /// that family (removed by the owner, left, or a stale snapshot).
    case notInFamily
    /// 426: this build is older than the server supports.
    case updateRequired
    /// 502 / 503 / 504: the single edge container restarting (a deploy) or a
    /// proxy timeout. An outage, not a refusal — queued like offline, the same
    /// call the app makes (NetworkError.serverUnavailable, pass 7).
    case serverUnavailable(Int)
    case server(Int, String)
    case transport(Error)

    /// Worth saving and sending later rather than reporting as a refusal.
    var isQueueable: Bool {
        switch self {
        case .transport, .serverUnavailable: return true
        default: return false
        }
    }

    var errorDescription: String? { message(ownerName: nil) }

    /// Plain words — never an HTTP code — matching the in-app mapping
    /// (ReceiverViewModel.checkInFailure).
    func message(ownerName: String?) -> String {
        let family = ownerName ?? "your family"
        switch self {
        case .notSignedIn:
            return "Open Daily OK on your iPhone and sign in first."
        case .locked:
            #if os(watchOS)
            return "Unlock Daily OK on your iPhone, then try again."
            #else
            return "Daily OK is locked. Open the app to unlock, then try again."
            #endif
        case .sessionExpired:
            return "You've been signed out. Open Daily OK on your iPhone to sign back in."
        case .badConfiguration:
            return "Daily OK isn't set up yet. Open the app once to finish setup."
        case .notInFamily:
            return "You're no longer part of this family's check-ins. Open Daily OK on your iPhone to see why."
        case .updateRequired:
            return "Please update Daily OK to keep checking in."
        case .serverUnavailable, .server, .transport:
            return "Couldn't reach Daily OK. Try again in a minute, or call \(family)."
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
    ///   - occurredAt: the moment the receiver actually tapped, for a check-in
    ///     being flushed from an offline queue. Omitted for a live check-in,
    ///     where the server's `now()` is the same instant (US-IOS147).
    ///   - slotKey: the window a queued tap answered. A live tap works it out
    ///     from the latest check-in request instead.
    ///   - timeout: per request. Widgets, Control Center and Siri get a short
    ///     budget from the system; 30 s per request (refresh → POST → 401 →
    ///     refresh → POST) could outlive it and lose the tap with nothing
    ///     saved. The whole call also stops retrying past ~2.5× this.
    @discardableResult
    static func checkIn(
        responseType: String = "ok",
        source: String = "app",
        batteryLevel: Double? = nil,
        occurredAt: Date? = nil,
        slotKey: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> SharedCheckInState {
        let deadline = Date().addingTimeInterval(timeout * 2.5)
        guard var state = SharedCheckInStore.load() else { throw SharedCheckInError.notSignedIn }
        // The session secrets live in the Keychain, not the snapshot plist. With
        // a snapshot present but no tokens, the user IS signed in but biometric
        // lock has withheld the tokens — surface a distinct "locked" message so
        // a Control Center / Siri tap doesn't tell an already-signed-in user to
        // "sign in first" (US-IOS128).
        guard var tokens = SharedKeychain.loadTokens() else { throw SharedCheckInError.locked }

        if tokens.isAccessTokenExpired {
            tokens = try await refreshSession(state, tokens: tokens, timeout: timeout)
        }

        // `[String: Any]`, not `[String: String]`, so numeric fields go on the
        // wire as JSON NUMBERS (US-IOS078). This path sent `String(battery)` —
        // `"battery_level": "0.62"` — and only worked because the edge function
        // still runs `coerceNumericFields`, a shim whose own comment says it is
        // there for "pre-US-IOS078 builds still in the wild". Every shipping
        // widget, Control Center, Siri and watch check-in was relying on the
        // backward-compatibility path rather than the current contract, so the
        // day that shim is retired the wrist tap breaks — and the in-app path,
        // which sends numbers, would keep working and hide it.
        var body: [String: Any] = [
            "receiver_id": state.receiverId,
            "family_id": state.familyId,
            "source": source,
            "response_type": responseType,
        ]
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = battery
        }
        // Without this the server stamps checked_in_at with now(), so a wrist
        // tap made at 23:55 and flushed after midnight is recorded as the next
        // day's check-in — leaving the day it was actually made looking missed,
        // and today looking answered when it is not (US-IOS147).
        if let occurredAt {
            body["occurred_at"] = iso8601UTC.string(from: occurredAt)
        }
        // Which window this answers. Without it the server dedups day-level: an
        // evening answer from the widget or watch found the morning row, added
        // nothing, and History counted the day as incomplete.
        if let slot = slotKey ?? (occurredAt == nil ? state.owedSlotKey() : nil) {
            body["slot_key"] = slot
        }

        do {
            do {
                try await postCheckIn(state: state, accessToken: tokens.accessToken, body: body, timeout: timeout)
            } catch SharedCheckInError.server(let code, _) where code == 401 {
                // Token may have expired between the check and the request —
                // refresh once and retry so a wrist/widget tap isn't lost (which
                // would leave the request pending and falsely escalate to the
                // owner). Not past the deadline, though: a surface the system is
                // about to kill is better off saving the tap than starting a
                // refresh it can't finish.
                guard Date() < deadline else { throw SharedCheckInError.transport(URLError(.timedOut)) }
                tokens = try await refreshSession(state, tokens: tokens, timeout: timeout)
                try await postCheckIn(state: state, accessToken: tokens.accessToken, body: body, timeout: timeout)
            }
        } catch SharedCheckInError.notInFamily {
            // Removed by the owner, or left: nothing on this device should keep
            // offering "I'm OK" for this family. Drop the snapshot so every
            // glanceable surface falls back to "Open Daily OK". The tokens stay
            // — the account is still valid, and the app re-publishes if the
            // person is added back.
            if SharedCheckInStore.load()?.familyId == state.familyId {
                SharedCheckInStore.clear()
            }
            throw SharedCheckInError.notInFamily
        }

        // Merge the done-state onto the FRESHEST snapshot (re-loaded inside
        // update()) instead of saving the whole `state` captured at the top of
        // this call: a concurrent phone `publish()` rewrites the entire snapshot
        // (e.g. a new nextCheckInAt / displayName), and saving our stale copy
        // would clobber it. This narrows — but does not fully close — the
        // cross-process write race (App Group writes aren't coordinated; see
        // SharedCheckInStore.update). The monotonic hasCheckedInToday flip is the
        // safety-relevant field and is resilient to a lost write (US-IOS129).
        let now = Date()

        // A check-in flushed for an EARLIER day answers that day, not this one.
        // Flipping `hasCheckedInToday` for it would put "all set" on the watch
        // face and the widget for a day the receiver has not answered — the
        // false reassurance US-IOS147 exists to remove, arriving through the
        // glanceable surfaces instead of the dashboard.
        let calendar = state.receiverCalendar
        let answersToday = occurredAt.map { calendar.isDate($0, inSameDayAs: now) } ?? true
        guard answersToday else {
            return SharedCheckInStore.load() ?? state
        }

        let isHelp = responseType != "ok"
        SharedCheckInStore.update { snapshot in
            snapshot.hasCheckedInToday = true
            snapshot.lastCheckInAt = now
            // "Help requested", not "You're all set", on every glanceable
            // surface. A plain OK after a help request doesn't clear it: the
            // server never downgrades a help row either.
            if isHelp {
                snapshot.helpKind = responseType
                snapshot.helpAt = now
            }
            snapshot.pendingSendSince = nil
            snapshot.lastFailureMessage = nil
            snapshot.lastFailureAt = nil
            // Drop a now-past reload anchor so a stale `nextCheckInAt` from a
            // prior config can't delay the new-day flip on glanceable surfaces;
            // the phone rewrites the real next time on its next `loadStatus`.
            if let next = snapshot.nextCheckInAt, next <= now {
                snapshot.nextCheckInAt = nil
            }
        }
        // Reflect the merged result; fall back to a locally-updated copy if the
        // snapshot was cleared concurrently (e.g. by sign-out).
        if let merged = SharedCheckInStore.load() {
            return merged
        }
        state.hasCheckedInToday = true
        state.lastCheckInAt = now
        state.updatedAt = now
        if isHelp {
            state.helpKind = responseType
            state.helpAt = now
        }
        return state
    }

    /// Posted (in-process) after this client rotated the session tokens. The
    /// watch listens and hands the new pair back to the phone, so the phone
    /// doesn't later spend the refresh token the watch already used.
    static let tokensRotated = Notification.Name("SharedCheckInClient.tokensRotated")

    /// Record a refusal on the snapshot so the widget can say "Didn't send"
    /// instead of silently showing the same button again.
    static func recordFailure(_ message: String, at date: Date = Date()) {
        SharedCheckInStore.update { snapshot in
            snapshot.lastFailureMessage = message
            snapshot.lastFailureAt = date
        }
    }

    /// Record that a tap was saved on this device and will be sent later.
    static func recordPendingSend(at date: Date = Date()) {
        SharedCheckInStore.update { snapshot in
            // Always today's stamp: a leftover from an earlier day would be
            // day-scoped away (hasPendingSend) and hide today's saved tap.
            snapshot.pendingSendSince = date
            snapshot.lastFailureMessage = nil
            snapshot.lastFailureAt = nil
        }
    }

    /// RFC 3339 in UTC, which is what the edge function's `Date.parse` accepts
    /// unambiguously.
    private static let iso8601UTC: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    // MARK: - Networking

    private static func postCheckIn(state: SharedCheckInState, accessToken: String, body: [String: Any], timeout: TimeInterval) async throws {
        guard let url = URL(string: "\(state.edgeFunctionsURL)/process-checkin-response") else {
            throw SharedCheckInError.badConfiguration
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
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
            throw mapStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Status → error. Pure, for tests.
    static func mapStatus(_ status: Int, body: String) -> SharedCheckInError {
        switch status {
        case 403: return .notInFamily
        case 426: return .updateRequired
        case 502, 503, 504: return .serverUnavailable(status)
        default: return .server(status, body)
        }
    }

    /// Refresh the Supabase access token using the refresh token and persist the
    /// rotated tokens back to the shared Keychain.
    private static func refreshSession(_ state: SharedCheckInState, tokens: SharedAuthTokens, timeout: TimeInterval) async throws -> SharedAuthTokens {
        guard let url = URL(string: "\(state.supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            throw SharedCheckInError.sessionExpired
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
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

        if let http = response as? HTTPURLResponse, [502, 503, 504].contains(http.statusCode) {
            // Auth is behind the same proxy: an outage, not a dead session.
            throw SharedCheckInError.serverUnavailable(http.statusCode)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // The refresh may have failed because a SIBLING surface (main app,
            // widget, another App Intent) refreshed concurrently and rotated this
            // refresh token out from under us — Supabase invalidates the old
            // token on use. Before declaring the session dead (which tells an
            // actually-signed-in user to "sign back in on your iPhone"), re-read
            // the shared Keychain: if that other surface already mirrored a fresh,
            // non-expired token, adopt it instead of forcing a spurious sign-out.
            if let reloaded = SharedKeychain.loadTokens(),
               reloaded.refreshToken != tokens.refreshToken,
               !reloaded.isAccessTokenExpired {
                return reloaded
            }
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
        NotificationCenter.default.post(name: tokensRotated, object: nil)
        return updated
    }
}
