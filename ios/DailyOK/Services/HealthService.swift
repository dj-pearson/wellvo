import Foundation
import os
#if canImport(HealthKit)
import HealthKit
#endif

/// US-IOS017 — optional, privacy-minimal Apple Health integration.
///
/// Strictly opt-in and receiver-controlled. We read ONE low-sensitivity metric
/// (today's step count) purely to derive a single boolean — "active today" —
/// which is the ONLY thing that leaves the device. No raw health samples are
/// ever uploaded. This is supplementary reassurance, NOT medical monitoring or
/// fall detection. Default is fully off; the receiver can revoke at any time.
@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()

    /// Local opt-in flag. Source of truth lives on the receiver's device so
    /// turning it off immediately stops all reporting (revoke at any time).
    private let optInKey = "health_sharing_enabled"

    /// Movement floor for "active today". Deliberately low and coarse — we only
    /// ever derive/transmit a boolean, never the step count itself.
    private let activeStepThreshold = 250

    @Published private(set) var isSharingEnabled: Bool

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    private init() {
        isSharingEnabled = UserDefaults.standard.bool(forKey: optInKey)
    }

    /// True only on devices that actually expose HealthKit data.
    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Turn sharing on (requesting permission) or off (clearing the local flag
    /// and deleting any previously-shared signals so revocation is complete).
    /// Returns true on success. When enabling fails (HealthKit permission
    /// denied/unavailable) it returns false so the UI can explain why instead of
    /// the toggle silently snapping back (US-IOS111). Disabling always succeeds.
    @discardableResult
    func setSharing(_ enabled: Bool) async -> Bool {
        if enabled {
            let granted = await requestAuthorization()
            guard granted else {
                // Permission denied — degrade cleanly, stay off.
                isSharingEnabled = false
                UserDefaults.standard.set(false, forKey: optInKey)
                return false
            }
            isSharingEnabled = true
            UserDefaults.standard.set(true, forKey: optInKey)
            await reportTodayIfEnabled()
            return true
        } else {
            isSharingEnabled = false
            UserDefaults.standard.set(false, forKey: optInKey)
            await revokeSharedSignals()
            return true
        }
    }

    /// Request read access to step count only. Returns false if HealthKit is
    /// unavailable or the user declines.
    private func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Compute today's "active" boolean from step count and upsert it. Safe to
    /// call often (e.g., on foreground / after a check-in); no-op when sharing
    /// is off or HealthKit data is unavailable.
    func reportTodayIfEnabled() async {
        guard isSharingEnabled, isHealthDataAvailable else { return }
        guard let active = await todayActive() else { return }
        await upload(active: active)
    }

    #if canImport(HealthKit)
    /// Sum today's steps and reduce to a boolean. Returns nil when no data /
    /// query fails so we never upload a misleading "inactive".
    private func todayActive() async -> Bool? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = sum.doubleValue(for: .count())
                continuation.resume(returning: Int(steps) >= self.activeStepThreshold)
            }
            store.execute(query)
        }
    }
    #else
    private func todayActive() async -> Bool? { nil }
    #endif

    private struct WellnessUpsert: Encodable {
        let receiver_id: String
        let family_id: String
        let signal_date: String
        let active: Bool
        let source: String
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func upload(active: Bool) async {
        guard let session = try? await SupabaseService.shared.client.auth.session,
              let family = try? await FamilyService.shared.getFamily() else { return }
        let payload = WellnessUpsert(
            receiver_id: session.user.id.uuidString,
            family_id: family.id.uuidString,
            signal_date: Self.dateFormatter.string(from: Date()),
            active: active,
            source: "healthkit"
        )
        do {
            try await SupabaseService.shared.client
                .from("wellness_signals")
                .upsert(payload, onConflict: "receiver_id,family_id,signal_date")
                .execute()
        } catch {
            // Best-effort; passive signal is non-critical — but log so a
            // persistently-failing upload is diagnosable.
            Log.general.error("Wellness signal upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove everything we've shared (full revoke).
    private func revokeSharedSignals() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        do {
            try await SupabaseService.shared.client
                .from("wellness_signals")
                .delete()
                .eq("receiver_id", value: session.user.id.uuidString)
                .execute()
        } catch {
            Log.general.error("Wellness signal revoke failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
