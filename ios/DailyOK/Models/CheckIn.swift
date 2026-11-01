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

    /// Short, localized mood name for pickers and summaries (US-IOS149 prep).
    /// Keyed (`mood.<case>.label`) because the English values collide with
    /// unrelated strings ("Good" is also a password-strength label) that need
    /// different translations. Display-only — the raw values above are the
    /// wire/disk format and are unchanged.
    var label: String {
        switch self {
        case .happy: return String(localized: "mood.happy.label", defaultValue: "Good", comment: "Mood option: feeling good")
        case .neutral: return String(localized: "mood.neutral.label", defaultValue: "Okay", comment: "Mood option: feeling okay")
        case .tired: return String(localized: "mood.tired.label", defaultValue: "Tired", comment: "Mood option")
        case .excited: return String(localized: "mood.excited.label", defaultValue: "Excited", comment: "Mood option")
        case .bored: return String(localized: "mood.bored.label", defaultValue: "Bored", comment: "Mood option")
        case .hungry: return String(localized: "mood.hungry.label", defaultValue: "Hungry", comment: "Mood option")
        case .scared: return String(localized: "mood.scared.label", defaultValue: "Scared", comment: "Mood option")
        case .havingFun: return String(localized: "mood.havingFun.label", defaultValue: "Having Fun", comment: "Mood option")
        case .unknown: return String(localized: "mood.unknown.label", defaultValue: "Unknown", comment: "Mood we could not recognise")
        }
    }

    /// Full localized sentence ("Feeling good") shown after a mood is picked.
    /// A whole sentence per mood rather than "Feeling \(label)" so translators
    /// can handle word order, gender and case agreement.
    var feelingSentence: String {
        switch self {
        case .happy: return String(localized: "Feeling good", comment: "Receiver's chosen mood, shown after check-in")
        case .neutral: return String(localized: "Feeling okay", comment: "Receiver's chosen mood, shown after check-in")
        case .tired: return String(localized: "Feeling tired", comment: "Receiver's chosen mood, shown after check-in")
        case .excited: return String(localized: "Feeling excited", comment: "Receiver's chosen mood, shown after check-in")
        case .bored: return String(localized: "Feeling bored", comment: "Receiver's chosen mood, shown after check-in")
        case .hungry: return String(localized: "Feeling hungry", comment: "Receiver's chosen mood, shown after check-in")
        case .scared: return String(localized: "Feeling scared", comment: "Receiver's chosen mood, shown after check-in")
        case .havingFun: return String(localized: "Feeling having fun", comment: "Receiver's chosen mood, shown after check-in")
        case .unknown: return String(localized: "Feeling unknown", comment: "Receiver's chosen mood, shown after check-in (unrecognised mood)")
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
        case .home: return String(localized: "Home", comment: "Location label")
        case .school: return String(localized: "School", comment: "Location label")
        case .friendsHouse: return String(localized: "Friend's House", comment: "Location label")
        case .park: return String(localized: "Park", comment: "Location label")
        case .store: return String(localized: "Store", comment: "Location label")
        case .other: return String(localized: "Other", comment: "Location label")
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
        case .pickingMeUp: return String(localized: "Pick me up!", comment: "Kid response button")
        case .canStayLonger: return String(localized: "Can I stay longer?", comment: "Kid response button")
        case .sos: return String(localized: "SOS!", comment: "Kid emergency response button")
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
