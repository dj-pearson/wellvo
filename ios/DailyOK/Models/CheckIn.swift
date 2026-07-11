import Foundation

enum Mood: String, Codable, CaseIterable {
    case happy
    case neutral
    case tired
    case excited
    case bored
    case hungry
    case scared
    case havingFun = "having_fun"
    /// A mood value this app version doesn't recognize (e.g. one the server
    /// added later — the enum already grew once in migration 00014). Decoded
    /// here instead of silently coercing to `.neutral`, and excluded from mood
    /// analytics so it can't skew the breakdown (US-IOS101).
    case unknown

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .neutral: return "😐"
        case .tired: return "😴"
        case .excited: return "🤩"
        case .bored: return "😒"
        case .hungry: return "🍕"
        case .scared: return "😰"
        case .havingFun: return "🎉"
        case .unknown: return "❓"
        }
    }

    var label: String {
        switch self {
        case .happy: return "Good"
        case .neutral: return "Okay"
        case .tired: return "Tired"
        case .excited: return "Excited"
        case .bored: return "Bored"
        case .hungry: return "Hungry"
        case .scared: return "Scared"
        case .havingFun: return "Having Fun"
        case .unknown: return "Unknown"
        }
    }

    static var standardMoods: [Mood] {
        [.happy, .neutral, .tired]
    }

    static var kidMoods: [Mood] {
        [.happy, .excited, .havingFun, .neutral, .bored, .hungry, .tired, .scared]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Mood(rawValue: rawValue) ?? .unknown
    }
}

enum ReceiverMode: String, Codable, CaseIterable {
    case standard
    case kid

    // Forgiving decode: a future receiver mode must not throw the whole
    // `ReceiverSettings` decode (which would revert every receiver in a batch
    // to standard mode). Unknown → `.standard`. No new case, so the picker's
    // `allCases` is unchanged.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReceiverMode(rawValue: raw) ?? .standard
    }
}

enum LocationLabel: String, Codable, CaseIterable {
    case home
    case school
    case friendsHouse = "friends_house"
    case park
    case store
    case other

    var label: String {
        switch self {
        case .home: return "Home"
        case .school: return "School"
        case .friendsHouse: return "Friend's House"
        case .park: return "Park"
        case .store: return "Store"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .school: return "building.columns.fill"
        case .friendsHouse: return "person.2.fill"
        case .park: return "tree.fill"
        case .store: return "cart.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}

enum KidResponseType: String, Codable, CaseIterable {
    case pickingMeUp = "picking_me_up"
    case canStayLonger = "can_stay_longer"
    case sos

    var label: String {
        switch self {
        case .pickingMeUp: return "Pick me up!"
        case .canStayLonger: return "Can I stay longer?"
        case .sos: return "SOS!"
        }
    }

    var icon: String {
        switch self {
        case .pickingMeUp: return "car.fill"
        case .canStayLonger: return "clock.fill"
        case .sos: return "exclamationmark.triangle.fill"
        }
    }
}

enum CheckInSource: String, Codable {
    case app
    case notification
    case onDemand = "on_demand"
    case needHelp = "need_help"
    case callMe = "call_me"
    // Out-of-process surfaces (US-IOS107). Backed by checkin_source enum values
    // added in migration 00046.
    case widget
    case control
    case siri

    // Forgiving decode: a row written by Android, a future server source, or a
    // notification action this build doesn't recognize must NOT throw (which
    // would surface a thrown check-in error for a check-in the server already
    // recorded, and stall the offline sync loop). Unknown → `.app` (US-IOS087).
    // These raw values are now a tolerant contract.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CheckInSource(rawValue: raw) ?? .app
    }
}

enum CheckInResponseType: String, Codable {
    case ok
    case needHelp = "need_help"
    case callMe = "call_me"

    // Unknown → `.ok` so an unrecognized response_type isn't shown as a scary
    // failure for a check-in that actually succeeded (US-IOS087).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CheckInResponseType(rawValue: raw) ?? .ok
    }
}

enum CheckInRequestStatus: String, Codable {
    case pending
    case checkedIn = "checked_in"
    case missed
    case expired

    // Forgiving decode: an unknown status (a future backend value) must not
    // throw the whole `CheckInRequest` decode. The consumers wrap that query in
    // `try?`, so a throw silently made the owner's escalation banner / Live
    // Activity and the receiver's "waiting" banner disappear. Unknown →
    // `.expired` so the request is treated as inactive — never a phantom
    // `.pending` escalation or a false `.checkedIn` resolution.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CheckInRequestStatus(rawValue: raw) ?? .expired
    }
}

enum CheckInRequestType: String, Codable {
    case scheduled
    case onDemand = "on_demand"

    // Forgiving decode: an unknown request type must not throw the
    // `CheckInRequest` decode. Unknown → `.scheduled`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CheckInRequestType(rawValue: raw) ?? .scheduled
    }
}

struct CheckIn: Codable, Identifiable {
    let id: UUID
    let receiverId: UUID
    let familyId: UUID
    let checkedInAt: Date
    let mood: Mood?
    let source: CheckInSource
    let scheduledFor: Date?
    let responseType: CheckInResponseType?
    let latitude: Double?
    let longitude: Double?
    let locationAccuracyMeters: Double?
    let distanceFromHomeMeters: Double?
    let locationLabel: String?
    let kidResponseType: String?

    enum CodingKeys: String, CodingKey {
        case id, mood, source, latitude, longitude
        case receiverId = "receiver_id"
        case familyId = "family_id"
        case checkedInAt = "checked_in_at"
        case scheduledFor = "scheduled_for"
        case responseType = "response_type"
        case locationAccuracyMeters = "location_accuracy_meters"
        case distanceFromHomeMeters = "distance_from_home_meters"
        case locationLabel = "location_label"
        case kidResponseType = "kid_response_type"
    }

    // Explicit memberwise initializer with defaults for the optional fields.
    // (Decodable's `init(from:)` is still synthesized separately.) This keeps
    // call sites that only care about the core fields — tests, widgets, and the
    // shared snapshot — concise instead of having to pass every location/response
    // field as nil.
    init(
        id: UUID,
        receiverId: UUID,
        familyId: UUID,
        checkedInAt: Date,
        mood: Mood? = nil,
        source: CheckInSource,
        scheduledFor: Date? = nil,
        responseType: CheckInResponseType? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracyMeters: Double? = nil,
        distanceFromHomeMeters: Double? = nil,
        locationLabel: String? = nil,
        kidResponseType: String? = nil
    ) {
        self.id = id
        self.receiverId = receiverId
        self.familyId = familyId
        self.checkedInAt = checkedInAt
        self.mood = mood
        self.source = source
        self.scheduledFor = scheduledFor
        self.responseType = responseType
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracyMeters = locationAccuracyMeters
        self.distanceFromHomeMeters = distanceFromHomeMeters
        self.locationLabel = locationLabel
        self.kidResponseType = kidResponseType
    }
}

struct CheckInRequest: Codable, Identifiable {
    let id: UUID
    let familyId: UUID
    let receiverId: UUID
    let requestedBy: UUID
    let type: CheckInRequestType
    var status: CheckInRequestStatus
    let createdAt: Date
    var respondedAt: Date?
    var escalationStep: Int
    var nextEscalationAt: Date?
    /// When set and in the future, the receiver has snoozed this request and
    /// escalation is deferred until then. `decodeIfPresent`-safe for older
    /// backends without the column.
    var snoozedUntil: Date?
    var snoozeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, status
        case familyId = "family_id"
        case receiverId = "receiver_id"
        case requestedBy = "requested_by"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case escalationStep = "escalation_step"
        case nextEscalationAt = "next_escalation_at"
        case snoozedUntil = "snoozed_until"
        case snoozeCount = "snooze_count"
    }
}
