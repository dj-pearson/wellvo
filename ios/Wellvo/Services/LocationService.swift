import Foundation
import CoreLocation
import Supabase

/// Manages location tracking for receiver safety features.
/// Handles permission requests, current location fetches for check-ins,
/// and periodic background location reporting for geofence monitoring.
actor LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let locationManager = CLLocationManager()
    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var currentLocationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.allowsBackgroundLocationUpdates = true
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

        var body: [String: String] = [
            "family_id": familyId.uuidString,
            "latitude": String(location.latitude),
            "longitude": String(location.longitude),
        ]
        if let accuracy = location.accuracy {
            body["accuracy_meters"] = String(accuracy)
        }
        if let battery = batteryLevel {
            body["battery_level"] = String(battery)
        }

        try? await supabase.functions.invoke(
            "report-location",
            options: .init(body: body)
        )
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task {
            await handleLocationUpdate(locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task {
            await handleLocationUpdate(nil)
        }
    }

    private func handleLocationUpdate(_ location: CLLocation?) {
        currentLocationContinuation?.resume(returning: location)
        currentLocationContinuation = nil
    }
}
