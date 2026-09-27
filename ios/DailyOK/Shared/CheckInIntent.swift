import AppIntents
import WidgetKit
import UserNotifications

/// The single check-in action shared across Siri, the Shortcuts app, the
/// interactive Home/Lock Screen widget, the iOS 18 Control Center control, and
/// the watch. Built once here so every surface behaves identically.
@available(iOS 16.0, watchOS 9.0, *)
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    static var description = IntentDescription(
        "Let your family know you're OK without opening the app."
    )

    /// We complete the check-in in the background — no need to launch the app.
    static var openAppWhenRun: Bool = false

    /// Which surface invoked this check-in ('widget' / 'control' / 'siri' /
    /// 'app'). A @Parameter so it survives the encode/decode that interactive
    /// widget buttons perform, letting analytics tell the surfaces apart
    /// (US-IOS107). Defaults to 'app' for the bare Shortcuts run.
    ///
    /// The Shortcuts editor shows it as free text, so anything can arrive here.
    /// It is normalised before it is sent (`CheckInSurface.normalized`): the
    /// server stores it in an ENUM column, and an unknown value used to fail
    /// every check-in from that shortcut with a 500.
    @Parameter(title: "Source", default: "app")
    var source: String

    init() {}
    init(source: String) { self.source = source }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let surface = CheckInSurface.normalized(source)
        let ownerName = SharedCheckInStore.load()?.ownerName
        do {
            // 8 s per request: a widget button or Control Center press runs on
            // a short system budget, and a tap that runs out of time must still
            // get as far as being saved below.
            let state = try await SharedCheckInClient.checkIn(source: surface, timeout: 8)
            ExtensionCheckInQueue.clearToday(calendar: state.receiverCalendar)
            await CheckInAftermathLite.clearReminders()
            // Refresh every glanceable surface so the status flips to "all set".
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "You're all set — your family has been notified.")
        } catch let error as SharedCheckInError where error.isQueueable {
            // Offline, or Daily OK was briefly unreachable. Save the tap; the app
            // sends it (with the time it was made) the next time it runs. The
            // widget shows "Saved — will send when you're online" meanwhile.
            if let state = SharedCheckInStore.load() {
                ExtensionCheckInQueue.enqueue(
                    OfflineCheckInMarker(
                        at: Date(), type: "ok",
                        receiverId: state.receiverId, familyId: state.familyId,
                        source: surface, slotKey: state.owedSlotKey()
                    ),
                    calendar: state.receiverCalendar
                )
                SharedCheckInClient.recordPendingSend()
                WidgetCenter.shared.reloadAllTimelines()
                let saved = "Saved on your iPhone — it will send when Daily OK can be reached. If it's urgent, call \(ownerName ?? "your family")."
                return .result(dialog: IntentDialog(stringLiteral: saved))
            }
            return .result(dialog: IntentDialog(stringLiteral: error.message(ownerName: ownerName)))
        } catch SharedCheckInError.notSignedIn {
            // No receiver snapshot. On an owner's or co-caregiver's phone that is
            // expected — "sign in first" told a signed-in owner something false.
            if SharedOwnerStore.load() != nil {
                return .result(dialog: "Check-ins from here are for the person being checked on. Open Daily OK to see how your family is doing.")
            }
            return .result(dialog: IntentDialog(stringLiteral: SharedCheckInError.notSignedIn.message(ownerName: nil)))
        } catch let error as SharedCheckInError {
            // A refusal. Put it on the widget too: a widget button never shows
            // this dialog, and the same "I'm OK" button coming back unchanged
            // read as "it worked".
            let message = error.message(ownerName: ownerName)
            if case .notInFamily = error {
                // The snapshot is already gone; the widget says "Open Daily OK".
            } else {
                SharedCheckInClient.recordFailure(message)
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            SharedCheckInClient.recordFailure("Your check-in didn't go through. Open Daily OK to try again.")
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Sorry, the check-in didn't go through. Open Daily OK to try again.")
        }
    }
}

/// The surfaces the server's `checkin_source` ENUM knows for an intent-driven
/// check-in (00037 / 00046). Pure, for tests.
enum CheckInSurface {
    static let known: Set<String> = ["app", "widget", "control", "siri", "watch"]

    static func normalized(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return known.contains(value) ? value : "app"
    }
}

/// What the app's `ReceiverCheckInAftermath` does about notifications, for a
/// check-in made from the widget, Control Center or Siri.
///
/// Before this, a receiver who answered from the widget kept yesterday's and
/// this morning's "please check in" banners on the Lock Screen and was buzzed
/// again later by the app's local fallback reminder (known gap 1). An app
/// extension addresses its containing app's notification center, so the
/// pending reminder can be withdrawn from here; when the intent runs in the app
/// process (Siri / Shortcuts) it is the same call. The app also re-derives the
/// reminder from server truth on its next load, so a missed removal here only
/// costs one reminder, never a check-in.
enum CheckInAftermathLite {
    /// Same identifier as PushNotificationService.fallbackReminderId.
    static let fallbackReminderId = "local-checkin-fallback"

    static func clearReminders() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [fallbackReminderId])
        let delivered = await center.deliveredNotifications()
        let ids = delivered
            .filter { $0.request.content.categoryIdentifier == "CHECKIN_REQUEST" }
            .map(\.request.identifier)
        if !ids.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}

/// "How's my family on Daily OK?" — the caregiver's most common question,
/// answered hands-free from the owner widget's snapshot. Siri used to have
/// nothing for owners and co-caregivers except "check in", which told a
/// signed-in owner to sign in.
@available(iOS 16.0, *)
struct FamilyStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Family Check-ins"
    static var description = IntentDescription("Hear who has checked in today.")
    static var openAppWhenRun: Bool = false
    /// Names and "needs help" are family health information: not spoken from a
    /// locked phone.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = SharedOwnerStore.load(), !state.receivers.isEmpty else {
            return .result(dialog: "Open Daily OK to see your family's check-ins.")
        }
        return .result(dialog: IntentDialog(stringLiteral: FamilyStatusSpeech.summary(state)))
    }
}

/// What Siri says for FamilyStatusIntent. Pure, for tests.
enum FamilyStatusSpeech {
    static func summary(_ state: SharedOwnerState, now: Date = Date(), viewerZone: TimeZone = .current) -> String {
        var lines: [String] = []
        // Whoever needs the owner first.
        let ordered = state.receivers.sorted { rank($0.status(asOf: now)) < rank($1.status(asOf: now)) }
        for r in ordered.prefix(6) {
            lines.append(line(for: r, now: now, viewerZone: viewerZone))
        }
        if state.receivers.count > 6 {
            lines.append("Open Daily OK for everyone else.")
        }
        let age = now.timeIntervalSince(state.updatedAt)
        if age >= 60 * 60 {
            let hours = Int(age / 3600)
            lines.append(hours == 1
                ? "This is from an hour ago. Open Daily OK for the latest."
                : "This is from \(hours) hours ago. Open Daily OK for the latest.")
        }
        return lines.joined(separator: " ")
    }

    private static func rank(_ status: String) -> Int {
        switch status {
        case "needs_help": return 0
        case "missed": return 1
        case "pending": return 2
        default: return 3
        }
    }

    private static func line(for r: SharedOwnerReceiver, now: Date, viewerZone: TimeZone) -> String {
        let status = r.status(asOf: now)
        switch status {
        case "checked_in":
            if let at = r.lastCheckIn(asOf: now) {
                return "\(r.name) checked in at \(r.timeText(at, viewerZone: viewerZone))."
            }
            return "\(r.name) checked in today."
        case "needs_help":
            switch r.helpKind {
            case "call_me": return "\(r.name) asked you to call."
            case "sos": return "\(r.name) sent an SOS."
            default: return "\(r.name) asked for help."
            }
        case "missed": return "\(r.name) missed today's check-in."
        case "stood_down": return "\(r.name) missed a check-in; alerts are stopped."
        case "upcoming": return "\(r.name)'s check-in isn't due yet."
        case "pending": return "\(r.name) hasn't checked in yet."
        default: return "No check-in from \(r.name) yet."
        }
    }
}
