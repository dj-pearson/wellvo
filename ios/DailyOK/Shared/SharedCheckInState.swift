import Foundation

/// A small, self-contained snapshot the main app publishes to the shared App
/// Group so out-of-process surfaces (App Intents / Siri, widgets, the Control
/// Center control, and the watch) can perform and display a check-in without
/// the full Supabase SDK or a live app session.
///
/// It carries only NON-SECRET identity, backend config, and glanceable status.
/// The Supabase session secrets (access/refresh token + expiry) are kept out of
/// this App Group `UserDefaults` plist — which is plaintext and lands in device
/// backups — and live in the encrypted Keychain via `SharedKeychain`. The phone
/// remains the source of truth: it rewrites this snapshot on every `loadStatus`,
/// and clears it (and the Keychain tokens) on sign-out.
struct SharedCheckInState: Codable, Equatable {
    // MARK: Identity
    var receiverId: String
    var familyId: String
    var displayName: String?
    var isKidMode: Bool

    // MARK: Backend config (so extensions don't depend on the host Info.plist)
    var supabaseURL: String
    var anonKey: String
    var edgeFunctionsURL: String

    // MARK: Today's status (for glanceable surfaces)
    var hasCheckedInToday: Bool
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var updatedAt: Date

    // MARK: Added in the extensions pass. Every one is optional with a nil
    // default, so a snapshot written by an older build still decodes (the
    // synthesized Codable uses decodeIfPresent for optionals) and the
    // memberwise initialiser keeps its old shape.

    /// The family owner's first name, for "Call Sarah" on the watch and the
    /// "didn't send" copy. nil → "your family".
    var ownerName: String? = nil
    /// The receiver's account zone (users.timezone). The server files check-ins
    /// by it, so "today" on every glanceable surface must use it too. nil → the
    /// device zone, which is what every build before this used.
    var timeZoneId: String? = nil
    /// Today's help signal, if the receiver asked for help: "need_help",
    /// "call_me" or "sos". A help request is not "You're all set".
    var helpKind: String? = nil
    var helpAt: Date? = nil
    /// When the latest check-in request reached this device (written by the
    /// Notification Service Extension on the phone and by the notification
    /// controller on the watch). A request newer than the last check-in means
    /// the family is asking again, so "all set" must give way to the button.
    var latestRequestAt: Date? = nil
    /// The "HH:mm" window that request is for, sent back as slot_key so an
    /// evening answer from the widget or watch is filed under the evening.
    var latestRequestSlotKey: String? = nil
    /// A tap from the widget / Control Center / Siri that couldn't reach the
    /// server and is saved on this phone, waiting for the app to send it.
    var pendingSendSince: Date? = nil
    /// The last refusal a glanceable surface should own up to ("Didn't send —
    /// open Daily OK"), and when. Cleared by the next success.
    var lastFailureMessage: String? = nil
    var lastFailureAt: Date? = nil
}

extension SharedCheckInState {
    /// The calendar "today" is measured in: the receiver's account zone when the
    /// phone published one, else the device's.
    var receiverCalendar: Calendar {
        var cal = Calendar.current
        if let id = timeZoneId, let zone = TimeZone(identifier: id) {
            cal.timeZone = zone
        }
        return cal
    }

    /// Whether today's check-in is actually done *as of `now`*, derived from the
    /// check-in's calendar day rather than trusting the persisted
    /// `hasCheckedInToday` flag on its own.
    ///
    /// `hasCheckedInToday` is only ever flipped *true* (by `markCheckedIn` /
    /// `SharedCheckInClient.checkIn`) and is never cleared at a local-midnight
    /// rollover for out-of-process surfaces — the phone clears it only when it
    /// next runs `loadStatus`. If the phone app isn't opened across midnight, a
    /// watch-only user would otherwise be shown a stale "all set" and have a
    /// real new-day check-in silently short-circuited (a false-escalation risk).
    ///
    /// Two more ways "done" stops being true without the phone app running:
    ///  - the family asked again (a check-in request that arrived after the
    ///    last check-in — an owner's "check on them now", or a later window);
    ///  - the day is measured in the receiver's account zone, which is what the
    ///    server files by, not the device's.
    ///
    /// `calendar` overrides the zone (tests); nil uses `receiverCalendar`.
    func isCheckedIn(asOf now: Date = Date(), calendar: Calendar? = nil) -> Bool {
        let cal = calendar ?? receiverCalendar
        guard hasCheckedInToday, let last = lastCheckInAt else { return false }
        guard cal.isDate(last, inSameDayAs: now) else { return false }
        if let asked = latestRequestAt, asked > last, asked <= now, cal.isDate(asked, inSameDayAs: now) {
            return false
        }
        return true
    }

    /// Today's help signal, day-scoped the same way. nil when none today.
    func helpRequested(asOf now: Date = Date(), calendar: Calendar? = nil) -> String? {
        let cal = calendar ?? receiverCalendar
        guard let helpKind, let helpAt, cal.isDate(helpAt, inSameDayAs: now) else { return nil }
        return helpKind
    }

    /// A tap saved on this device for today that hasn't reached the server.
    func hasPendingSend(asOf now: Date = Date(), calendar: Calendar? = nil) -> Bool {
        let cal = calendar ?? receiverCalendar
        guard let pendingSendSince else { return false }
        return cal.isDate(pendingSendSince, inSameDayAs: now)
    }

    /// A refusal to show, only while it is today's news and nothing has landed
    /// since.
    func failureMessage(asOf now: Date = Date(), calendar: Calendar? = nil) -> String? {
        let cal = calendar ?? receiverCalendar
        guard let message = lastFailureMessage, let at = lastFailureAt,
              cal.isDate(at, inSameDayAs: now) else { return nil }
        if let last = lastCheckInAt, last >= at { return nil }
        return message
    }

    /// The slot key to send with a live check-in: the window the latest request
    /// asked about, while that request is still unanswered today.
    func owedSlotKey(asOf now: Date = Date(), calendar: Calendar? = nil) -> String? {
        let cal = calendar ?? receiverCalendar
        guard let key = latestRequestSlotKey, !key.isEmpty,
              let asked = latestRequestAt, cal.isDate(asked, inSameDayAs: now) else { return nil }
        if let last = lastCheckInAt, last >= asked { return nil }
        return key
    }
}

/// Read/write access to the shared check-in snapshot. Safe to call from any
/// target that links the shared files and has the App Group entitlement.
enum SharedCheckInStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> SharedCheckInState? {
        guard let data = SharedAppGroup.defaults?.data(forKey: SharedAppGroup.Key.checkInState) else {
            return nil
        }
        return try? decoder.decode(SharedCheckInState.self, from: data)
    }

    static func save(_ state: SharedCheckInState) {
        guard let data = try? encoder.encode(state) else { return }
        SharedAppGroup.defaults?.set(data, forKey: SharedAppGroup.Key.checkInState)
    }

    /// Mutate the existing snapshot in place. No-op if none exists yet.
    ///
    /// NOTE: this load→mutate→save is NOT serialized across processes. The app,
    /// widgets, Control Center, App Intents, and the watch all write this App
    /// Group value, so a concurrent full-snapshot `save(...)` from the phone can
    /// land between this `load()` and `save(...)` and be lost. Today that only
    /// risks `nextCheckInAt` being briefly clobbered/resurrected (a cosmetic
    /// new-day rollover glitch on glanceable surfaces) — the safety-relevant
    /// `hasCheckedInToday = true` flip is monotonic, so a lost write self-heals
    /// on the next `load`. A robust fix would coordinate these writes with
    /// `NSFileCoordinator`; deferred until it can be exercised on-device across
    /// the extension surfaces (tight time budgets there make a blind change
    /// risky).
    static func update(_ mutate: (inout SharedCheckInState) -> Void) {
        guard var state = load() else { return }
        mutate(&state)
        state.updatedAt = Date()
        save(state)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: SharedAppGroup.Key.checkInState)
    }
}
