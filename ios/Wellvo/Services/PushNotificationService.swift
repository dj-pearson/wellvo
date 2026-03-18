import Foundation
import UserNotifications
import UIKit
import Supabase

actor PushNotificationService {
    static let shared = PushNotificationService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func requestPermission() async -> Bool {
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
            print("Notification permission error: \(error.localizedDescription)")
            return false
        }
    }

    func registerToken(_ token: String) async {
        guard let session = try? await supabase.auth.session else { return }

        do {
            try await supabase
                .from("push_tokens")
                .upsert([
                    "user_id": session.user.id.uuidString,
                    "token": token,
                    "platform": "ios",
                    "is_active": "true",
                ])
                .execute()
        } catch {
            print("Failed to register push token: \(error.localizedDescription)")
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}
