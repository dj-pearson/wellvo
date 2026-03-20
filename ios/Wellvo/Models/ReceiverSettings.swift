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
    var receiverMode: ReceiverMode

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
        case receiverMode = "receiver_mode"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        familyMemberId = try container.decode(UUID.self, forKey: .familyMemberId)
        checkinTime = try container.decode(String.self, forKey: .checkinTime)
        timezone = try container.decode(String.self, forKey: .timezone)
        gracePeriodMinutes = try container.decode(Int.self, forKey: .gracePeriodMinutes)
        reminderIntervalMinutes = try container.decode(Int.self, forKey: .reminderIntervalMinutes)
        escalationEnabled = try container.decode(Bool.self, forKey: .escalationEnabled)
        quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)
        quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)
        moodTrackingEnabled = try container.decode(Bool.self, forKey: .moodTrackingEnabled)
        smsEscalationEnabled = try container.decode(Bool.self, forKey: .smsEscalationEnabled)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        locationTrackingEnabled = try container.decode(Bool.self, forKey: .locationTrackingEnabled)
        homeLatitude = try container.decodeIfPresent(Double.self, forKey: .homeLatitude)
        homeLongitude = try container.decodeIfPresent(Double.self, forKey: .homeLongitude)
        geofenceRadiusMeters = try container.decode(Int.self, forKey: .geofenceRadiusMeters)
        locationAlertEnabled = try container.decode(Bool.self, forKey: .locationAlertEnabled)
        receiverMode = try container.decodeIfPresent(ReceiverMode.self, forKey: .receiverMode) ?? .standard
    }
}
