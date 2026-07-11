import Foundation
import UserNotifications
import UIKit
import Supabase

actor PushNotificationService {
    static let shared = PushNotificationService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func requestPermission() async throws -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            throw DailyOKError.network(error)
        }
    }

    func registerToken(_ token: String) async throws {
        guard let session = try? await supabase.auth.session else {
            throw DailyOKError.auth("Not authenticated")
        }

        // Check if token has changed before sending to server
        // Migrate: check old UserDefaults first, then Keychain
        if let oldToken = UserDefaults.standard.string(forKey: "lastPushToken") {
            _ = KeychainService.save(key: "lastPushToken", value: oldToken)
            UserDefaults.standard.removeObject(forKey: "lastPushToken")
        }
        let storedToken = KeychainService.load(key: "lastPushToken")
        guard token != storedToken else { return }

        do {
            // Deactivate this user's OTHER iOS tokens (exclude the one we're
            // about to register) so the live token is never momentarily marked
            // inactive between this update and the upsert below.
            try await supabase
                .from("push_tokens")
                .update(["is_active": "false"])
                .eq("user_id", value: session.user.id.uuidString)
                .eq("platform", value: "ios")
                .neq("token", value: token)
                .execute()

            // Register (or re-activate) the current token.
            try await supabase
                .from("push_tokens")
                .upsert([
                    "user_id": session.user.id.uuidString,
                    "token": token,
                    "platform": "ios",
                    "is_active": "true",
                ])
                .execute()

            _ = KeychainService.save(key: "lastPushToken", value: token)
        } catch {
            throw DailyOKError.network(error)
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Local Fallback Reminder

    private static let fallbackReminderId = "local-checkin-fallback"

    /// Schedule a single local reminder as a safety net in case the server-side
    /// push never arrives (edge function down, stale APNs token, etc.). It's a
    /// one-shot for the next occurrence — `ReceiverViewModel` reschedules it on
    /// every load and cancels it once the receiver has checked in, so it won't
    /// double up with a working server push.
    func scheduleLocalCheckinFallback(at date: Date, isKidMode: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.fallbackReminderId])

        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = isKidMode ? "Don't forget! 👋" : "Reminder: Check in"
        content.body = isKidMode
            ? "Tap to let your family know you're OK."
            : "You haven't checked in yet. Tap to let your family know you're OK."
        content.sound = .default
        content.categoryIdentifier = "CHECKIN_REQUEST"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.fallbackReminderId, content: content, trigger: trigger)

        try? await center.add(request)
    }

    func cancelLocalCheckinFallback() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.fallbackReminderId])
    }

    /// Immediately alert the receiver that a notification check-in response
    /// couldn't be sent. A tap on "I'm OK" / "I Need Help" / "Call Me" from the
    /// lock screen while offline previously failed silently — the receiver (and,
    /// for an urgent response, they alone) had no way to know their family was
    /// never notified. This surfaces that so they can retry or reach out another
    /// way instead of assuming the message got through.
    func presentCheckInResponseFailed(urgent: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = urgent ? "Your response didn't send" : "Check-in didn't go through"
        content.body = urgent
            ? "You appear to be offline, so your family wasn't notified. Open Daily OK to try again, or reach them another way."
            : "You appear to be offline and we couldn't save your check-in. Please open Daily OK and try again."
        content.sound = .default
        // nil trigger = deliver immediately.
        let request = UNNotificationRequest(
            identifier: "checkin-response-failed",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
