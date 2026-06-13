import Foundation

struct DailyOKAlert: Codable, Identifiable {
    let id: UUID
    let familyId: UUID
    let receiverId: UUID
    let type: String
    let title: String
    let message: String
    let data: [String: Double]?
    var isRead: Bool
    let createdAt: Date
    // US-IOS013 multi-caregiver acknowledgement. Nullable / additive — older
    // backends omit these keys and the ack UI simply doesn't render.
    var acknowledgedBy: UUID?
    var acknowledgedAt: Date?
    var acknowledgedByName: String?

    /// True once any caregiver has tapped "I've got this".
    var isAcknowledged: Bool { acknowledgedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, type, title, message, data
        case familyId = "family_id"
        case receiverId = "receiver_id"
        case isRead = "is_read"
        case createdAt = "created_at"
        case acknowledgedBy = "acknowledged_by"
        case acknowledgedAt = "acknowledged_at"
        case acknowledgedByName = "acknowledged_by_name"
    }
}
