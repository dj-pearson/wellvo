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

        try? await supabase.functions.invoke(
            "report-location",
            options: .init(body: body)
        )
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
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        guard lat >= -90, lat <= 90, lng >= -180, lng <= 180 else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let battery: Double? = (batteryLevel >= 0 && batteryLevel <= 1) ? Double(batteryLevel) : nil

        var body: [String: String] = [
            "family_id": familyId.uuidString,
            "latitude": String(lat),
            "longitude": String(lng),
        ]
        let accuracy = location.horizontalAccuracy
        if accuracy >= 0, accuracy <= 100000 {
            body["accuracy_meters"] = String(accuracy)
        }
        if let battery = battery {
            body["battery_level"] = String(battery)
        }

        // Use a background task to ensure the network call completes
        let bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        Task {
            try? await supabase.functions.invoke(
                "report-location",
                options: .init(body: body)
            )
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
        // Auto-start significant location monitoring once "Always" permission is granted
        if manager.authorizationStatus == .authorizedAlways,
           let familyId = activeFamilyId,
           !isMonitoringSignificantChanges {
            startBackgroundMonitoring(familyId: familyId)
        }
    }
}
