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
            throw WellvoError.network(error)
        }
    }

    func registerToken(_ token: String) async throws {
        guard let session = try? await supabase.auth.session else {
            throw WellvoError.auth("Not authenticated")
        }

        // Check if token has changed before sending to server
        let storedToken = UserDefaults.standard.string(forKey: "lastPushToken")
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

            UserDefaults.standard.set(token, forKey: "lastPushToken")
        } catch {
            throw WellvoError.network(error)
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}
