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
        self = Mood(rawValue: rawValue) ?? .neutral
    }
}

enum ReceiverMode: String, Codable, CaseIterable {
    case standard
    case kid
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
}

enum CheckInResponseType: String, Codable {
    case ok
    case needHelp = "need_help"
    case callMe = "call_me"
}

enum CheckInRequestStatus: String, Codable {
    case pending
    case checkedIn = "checked_in"
    case missed
    case expired
}

enum CheckInRequestType: String, Codable {
    case scheduled
    case onDemand = "on_demand"
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

    enum CodingKeys: String, CodingKey {
        case id, type, status
        case familyId = "family_id"
        case receiverId = "receiver_id"
        case requestedBy = "requested_by"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case escalationStep = "escalation_step"
        case nextEscalationAt = "next_escalation_at"
    }
}
