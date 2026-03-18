import Foundation

struct WellvoAlert: Codable, Identifiable {
    let id: UUID
    let familyId: UUID
    let receiverId: UUID
    let type: String
    let title: String
    let message: String
    let data: [String: Double]?
    var isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, title, message, data
        case familyId = "family_id"
        case receiverId = "receiver_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}
