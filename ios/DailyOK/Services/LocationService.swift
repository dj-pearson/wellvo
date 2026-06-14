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
    private var currentLocationContinuation: CheckedContinuation<CLLocation?, Never>?

    /// The family ID to report background location updates for.
    /// Set this when the receiver logs in and their family is known.
    var activeFamilyId: UUID?

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
            // Guard against a second call arriving before the first resolves:
            // overwriting `currentLocationContinuation` would leak the pending
            // one (a hard runtime trap) and hang the first caller forever. If a
            // request is already in flight, bail out for this caller instead.
            if currentLocationContinuation != nil {
                continuation.resume(returning: nil)
                return
            }
            currentLocationContinuation = continuation
            locationManager.requestLocation()
        }

        guard let loc = location else { return nil }

        return CheckInLocation(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy
        )
    }

    // MARK: - Report Location to Server

    func reportLocation(familyId: UUID, batteryLevel: Double? = nil) async {
        guard let location = await getCurrentLocation() else { return }

        // Validate location bounds before sending
        guard location.latitude >= -90, location.latitude <= 90,
              location.longitude >= -180, location.longitude <= 180 else { return }

        var body: [String: String] = [
            "family_id": familyId.uuidString,
            "latitude": String(location.latitude),
            "longitude": String(location.longitude),
        ]
        if let accuracy = location.accuracy, accuracy >= 0, accuracy <= 100000 {
            body["accuracy_meters"] = String(accuracy)
        }
        if let battery = batteryLevel, battery >= 0, battery <= 1 {
            body["battery_level"] = String(battery)
        }

        try? await EdgeFunctionsClient.invoke("report-location", body: body)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // If we have a pending one-shot request, fulfill it
        if let continuation = currentLocationContinuation {
            continuation.resume(returning: locations.last)
            currentLocationContinuation = nil
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

        var body: [String: String] = [
            "family_id": familyId.uuidString,
            "latitude": String(lat),
            "longitude": String(lng),
        ]
        let accuracy = location.horizontalAccuracy
        if accuracy >= 0, accuracy <= 100000 {
            // Reported accuracy can't be finer than the coarsening we applied.
            body["accuracy_meters"] = String(max(accuracy, 110))
        }
        if let battery = battery {
            body["battery_level"] = String(battery)
        }

        // Use a background task to ensure the network call completes
        let bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        Task {
            try? await EdgeFunctionsClient.invoke("report-location", body: body)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = currentLocationContinuation {
            continuation.resume(returning: nil)
            currentLocationContinuation = nil
        }
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
