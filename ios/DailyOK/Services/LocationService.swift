import Foundation
import CoreLocation
import UIKit
import Supabase

/// Manages location tracking for receiver safety features.
/// Handles permission requests, current location fetches for check-ins,
/// and background significant location change monitoring for geofence alerts.
class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let locationManager = CLLocationManager()
    private var supabase: SupabaseClient { SupabaseService.shared.client }

    /// Guards `currentLocationContinuation` / `currentRequestID`. CoreLocation
    /// delivers delegate callbacks on the manager's run-loop thread while
    /// `getCurrentLocation()` runs on an arbitrary async executor, so without a
    /// lock the check-then-set and the delegate's take-then-resume can race —
    /// double-resuming a CheckedContinuation (a hard runtime trap) or leaking it.
    private let continuationLock = NSLock()
    private var currentLocationContinuation: CheckedContinuation<CLLocation?, Never>?
    /// Monotonic id for the in-flight one-shot request, so a timed-out earlier
    /// request can't resolve a newer caller's continuation.
    private var currentRequestID = 0

    /// The family ID to report background location updates for.
    /// Set this when the receiver logs in and their family is known.
    ///
    /// Written from the caller's thread (`startBackgroundMonitoring`) and read on
    /// Core Location's delegate queue (`didUpdateLocations` /
    /// `didChangeAuthorization`), so access is serialized behind `stateLock` — a
    /// bare `UUID?` read/write across threads is a data race (a torn read could
    /// report a background location to the wrong/nil family, or trap).
    var activeFamilyId: UUID? {
        get { stateLock.withLock { _activeFamilyId } }
        set { stateLock.withLock { _activeFamilyId = newValue } }
    }
    private let stateLock = NSLock()
    private var _activeFamilyId: UUID?

    /// Whether background monitoring is currently active.
    private(set) var isMonitoringSignificantChanges = false

    /// Last background significant-change report, used to throttle clustered
    /// callbacks (Core Location can deliver several in quick succession).
    private var lastBackgroundReportAt: Date?
    private var lastBackgroundReportLocation: CLLocation?

    /// Reduce coordinate precision to ~3 decimal places (~110 m) — the
    /// resolution this safety feature actually needs — so a vulnerable user's
    /// full-resolution movements aren't continuously uploaded.
    private func coarsen(_ coordinate: Double) -> Double {
        (coordinate * 1000).rounded() / 1000
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Permission

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Background Significant Location Monitoring

    /// Start monitoring for significant location changes (500m+ moves).
    /// This works even when the app is killed — iOS relaunches it.
    /// Requires "Always" location permission.
    func startBackgroundMonitoring(familyId: UUID) {
        activeFamilyId = familyId
        guard authorizationStatus == .authorizedAlways else {
            requestAlwaysPermission()
            return
        }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }

        locationManager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
    }

    func stopBackgroundMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
    }

    // MARK: - Get Current Location (for check-in)

    func getCurrentLocation() async -> CheckInLocation? {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            return nil
        }

        let location: CLLocation? = await withCheckedContinuation { continuation in
            continuationLock.lock()
            // Guard against a second call arriving before the first resolves:
            // overwriting `currentLocationContinuation` would leak the pending
            // one and hang the first caller forever. If a request is already in
            // flight, bail out for this caller instead.
            if currentLocationContinuation != nil {
                continuationLock.unlock()
                continuation.resume(returning: nil)
                return
            }
            currentRequestID &+= 1
            let requestID = currentRequestID
            currentLocationContinuation = continuation
            continuationLock.unlock()
            locationManager.requestLocation()

            // Safety net: CoreLocation occasionally never calls back (no fix, no
            // error). Don't leak the continuation — which would hang this caller
            // AND block every future one-shot request. Resume nil after a
            // timeout if this exact request is still pending.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                _ = self?.resolvePendingLocation(nil, ifRequestID: requestID)
            }
        }

        guard let loc = location else { return nil }

        // Coarsen to ~110 m before it leaves this method so EVERY foreground /
        // check-in consumer uploads only approximate position — matching the
        // background path and the Coarse-only declaration in PrivacyInfo.xcprivacy
        // (US-IOS086). kCLLocationAccuracyHundredMeters is only a request, so the
        // coarsening is applied explicitly here and accuracy can't claim finer
        // than what we actually upload.
        return CheckInLocation(
            latitude: coarsen(loc.coordinate.latitude),
            longitude: coarsen(loc.coordinate.longitude),
            accuracy: loc.horizontalAccuracy >= 0 ? max(loc.horizontalAccuracy, 110) : nil
        )
    }

    /// Atomically take the pending one-shot continuation and resume it exactly
    /// once. Returns true if a continuation was resumed (so the caller knows the
    /// callback was a one-shot request rather than a background update). When
    /// `ifRequestID` is set, only resolves if it still matches the in-flight
    /// request — so a timed-out earlier request can't cancel a newer one.
    @discardableResult
    private func resolvePendingLocation(_ location: CLLocation?, ifRequestID requestID: Int? = nil) -> Bool {
        continuationLock.lock()
        if let requestID, requestID != currentRequestID {
            continuationLock.unlock()
            return false
        }
        guard let continuation = currentLocationContinuation else {
            continuationLock.unlock()
            return false
        }
        currentLocationContinuation = nil
        continuationLock.unlock()
        continuation.resume(returning: location)
        return true
    }

    // MARK: - Report Location to Server

    func reportLocation(familyId: UUID, batteryLevel: Double? = nil) async {
        guard let location = await getCurrentLocation() else { return }

        // Validate location bounds before sending
        guard location.latitude >= -90, location.latitude <= 90,
              location.longitude >= -180, location.longitude <= 180 else { return }

        var body: [String: JSONValue] = [
            "family_id": .string(familyId.uuidString),
            "latitude": .double(location.latitude),
            "longitude": .double(location.longitude),
        ]
        if let accuracy = location.accuracy, accuracy >= 0, accuracy <= 100000 {
            body["accuracy_meters"] = .double(accuracy)
        }
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = .double(battery)
        }

        try? await EdgeFunctionsClient.invoke("report-location", json: body)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // If we have a pending one-shot request, fulfill it.
        if resolvePendingLocation(locations.last) {
            return
        }

        // Otherwise this is a background significant location change — report it
        guard let location = locations.last, let familyId = activeFamilyId else { return }

        // Validate location bounds before sending
        let rawLat = location.coordinate.latitude
        let rawLng = location.coordinate.longitude
        guard rawLat >= -90, rawLat <= 90, rawLng >= -180, rawLng <= 180 else { return }

        // Throttle clustered significant-change callbacks: skip a report if it's
        // been under 5 minutes AND we've moved under 150 m since the last one.
        let now = Date()
        if let lastAt = lastBackgroundReportAt, let lastLoc = lastBackgroundReportLocation {
            if now.timeIntervalSince(lastAt) < 300, location.distance(from: lastLoc) < 150 {
                return
            }
        }
        lastBackgroundReportAt = now
        lastBackgroundReportLocation = location

        // Coarsen coordinates to ~110 m before upload — this feature only needs
        // approximate position, not the user's exact whereabouts.
        let lat = coarsen(rawLat)
        let lng = coarsen(rawLng)

        let batteryLevel = UIDevice.current.batteryLevel
        let battery: Double? = (batteryLevel >= 0 && batteryLevel <= 1) ? Double(batteryLevel) : nil

        var body: [String: JSONValue] = [
            "family_id": .string(familyId.uuidString),
            "latitude": .double(lat),
            "longitude": .double(lng),
        ]
        let accuracy = location.horizontalAccuracy
        if accuracy >= 0, accuracy <= 100000 {
            // Reported accuracy can't be finer than the coarsening we applied.
            body["accuracy_meters"] = .double(max(accuracy, 110))
        }
        if let battery = battery {
            body["battery_level"] = .double(battery)
        }

        // Use a background task to ensure the network call completes. Provide a
        // real expiration handler: if the OS reclaims background time before the
        // upload finishes, end the task cleanly rather than being force-terminated
        // with it outstanding (a nil handler). Both the handler and the
        // completion below run on the main thread, so the shared bgTask isn't
        // raced.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "report-location") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }

        Task {
            try? await EdgeFunctionsClient.invoke("report-location", json: body)
            await MainActor.run {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resolvePendingLocation(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Resume monitoring once "Always" is granted ONLY if the user has
        // already opted into location sharing — i.e. `activeFamilyId` was set by
        // an explicit `startBackgroundMonitoring(...)` call. Granting the OS
        // permission alone (with no in-app opt-in) must not silently begin
        // tracking, so we never set `activeFamilyId` here.
        if manager.authorizationStatus == .authorizedAlways,
           let familyId = activeFamilyId,
           !isMonitoringSignificantChanges {
            startBackgroundMonitoring(familyId: familyId)
        }
    }
}
