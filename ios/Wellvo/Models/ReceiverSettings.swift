import Foundation

struct ReceiverSettings: Codable, Identifiable {
    let id: UUID
    let familyMemberId: UUID
    var checkinTime: String // HH:mm format
    var timezone: String
    var gracePeriodMinutes: Int
    var reminderIntervalMinutes: Int
    var escalationEnabled: Bool
    var quietHoursStart: String? // HH:mm
    var quietHoursEnd: String? // HH:mm
    var moodTrackingEnabled: Bool
    var smsEscalationEnabled: Bool
    var isActive: Bool
    var locationTrackingEnabled: Bool
    var homeLatitude: Double?
    var homeLongitude: Double?
    var geofenceRadiusMeters: Int
    var locationAlertEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, timezone
        case familyMemberId = "family_member_id"
        case checkinTime = "checkin_time"
        case gracePeriodMinutes = "grace_period_minutes"
        case reminderIntervalMinutes = "reminder_interval_minutes"
        case escalationEnabled = "escalation_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case moodTrackingEnabled = "mood_tracking_enabled"
        case smsEscalationEnabled = "sms_escalation_enabled"
        case isActive = "is_active"
        case locationTrackingEnabled = "location_tracking_enabled"
        case homeLatitude = "home_latitude"
        case homeLongitude = "home_longitude"
        case geofenceRadiusMeters = "geofence_radius_meters"
        case locationAlertEnabled = "location_alert_enabled"
    }
}
