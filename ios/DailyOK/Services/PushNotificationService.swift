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
            // Deactivate old tokens for this user on this platform
            try await supabase
                .from("push_tokens")
                .update(["is_active": "false"])
                .eq("user_id", value: session.user.id.uuidString)
                .eq("platform", value: "ios")
                .execute()

            // Register new token
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
}
