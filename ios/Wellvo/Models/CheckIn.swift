import Foundation

enum Mood: String, Codable, CaseIterable {
    case happy
    case neutral
    case tired
}

enum CheckInSource: String, Codable {
    case app
    case notification
    case onDemand = "on_demand"
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

    enum CodingKeys: String, CodingKey {
        case id, mood, source
        case receiverId = "receiver_id"
        case familyId = "family_id"
        case checkedInAt = "checked_in_at"
        case scheduledFor = "scheduled_for"
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
