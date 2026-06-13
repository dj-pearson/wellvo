import Foundation

/// US-IOS016 — a shared note on a receiver's care timeline. Authored by a
/// caregiver (owner/viewer), visible to the whole care team.
struct CareNote: Codable, Identifiable, Equatable {
    let id: UUID
    let familyId: UUID
    let receiverId: UUID
    let authorId: UUID
    let authorName: String
    var body: String
    let createdAt: Date
    var updatedAt: Date

    var wasEdited: Bool { updatedAt.timeIntervalSince(createdAt) > 1 }

    enum CodingKeys: String, CodingKey {
        case id, body
        case familyId = "family_id"
        case receiverId = "receiver_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
