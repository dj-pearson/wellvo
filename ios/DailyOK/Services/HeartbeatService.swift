import Foundation
import UIKit
import Supabase
import os

/// Periodically reports app activity (last-seen), battery level, and app version
/// to the server so owners can see when a receiver was last active.
@MainActor
final class HeartbeatService {
    static let shared = HeartbeatService()

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var timer: Timer?
    private let interval: TimeInterval = 15 * 60 // 15 minutes
    private var connectivityObserver: NSObjectProtocol?

    func start() {
        // Enable battery monitoring once here rather than re-toggling it on every
        // heartbeat tick.
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Idempotent: if the periodic timer is already running, don't fire a
        // second initial heartbeat or schedule a duplicate timer (US-IOS098).
        guard timer == nil else { return }

        // Send initial heartbeat
        Task { await sendHeartbeat() }

        // Schedule periodic heartbeats
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.sendHeartbeat() }
        }

        // The repeating Timer no-ops while offline (and is suspended in the
        // background), so a receiver who was offline for a long foreground
        // stretch looks stale until the next tick. Re-anchor last_seen the moment
        // connectivity returns (US-IOS136). Guarded by `timer == nil` above so we
        // never double-register.
        if connectivityObserver == nil {
            connectivityObserver = NotificationCenter.default.addObserver(
                forName: OfflineCheckInService.connectivityRestored,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.sendHeartbeat() }
            }
        }
    }

    /// Re-anchor `last_seen_at` when the app returns to the foreground. The
    /// repeating Timer is suspended while backgrounded, so without this a
    /// receiver who opens the app after hours away still looks stale until the
    /// next tick fires (US-IOS098). Safe to call any time the app becomes active.
    func appBecameActive() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        Task { await sendHeartbeat() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let connectivityObserver {
            NotificationCenter.default.removeObserver(connectivityObserver)
            self.connectivityObserver = nil
        }
    }

    func sendHeartbeat() async {
        guard (try? await supabase.auth.session) != nil else { return }

        let batteryLevel = UIDevice.current.batteryLevel
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        var body: [String: JSONValue] = [:]
        if batteryLevel >= 0 {
            // battery_level on the wire as a JSON number (US-IOS078); the
            // heartbeat validator requires typeof === "number".
            body["battery_level"] = .double(Double(batteryLevel))
        }
        if let version = appVersion {
            body["app_version"] = .string(version)
        }

        do {
            try await EdgeFunctionsClient.invoke("heartbeat", json: body)
        } catch {
            // Heartbeat drives the owner's "last seen" — a silent failure makes a
            // receiver look inactive. Log it (non-fatal; next tick retries).
            Log.general.error("Heartbeat failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
