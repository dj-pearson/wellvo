import Foundation
import UIKit
import Supabase

/// Periodically reports app activity (last-seen), battery level, and app version
/// to the server so owners can see when a receiver was last active.
@MainActor
final class HeartbeatService {
    static let shared = HeartbeatService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var timer: Timer?
    private let interval: TimeInterval = 15 * 60 // 15 minutes

    func start() {
        // Send initial heartbeat
        Task { await sendHeartbeat() }

        // Schedule periodic heartbeats
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.sendHeartbeat() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sendHeartbeat() async {
        guard (try? await supabase.auth.session) != nil else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        var body: [String: String] = [:]
        if batteryLevel >= 0 {
            body["battery_level"] = String(Double(batteryLevel))
        }
        if let version = appVersion {
            body["app_version"] = version
        }

        try? await supabase.functions.invoke(
            "heartbeat",
            options: .init(body: body)
        )
    }
}
