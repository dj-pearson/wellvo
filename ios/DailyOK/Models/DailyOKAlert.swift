import Foundation

struct DailyOKAlert: Codable, Identifiable {
    let id: UUID
    let familyId: UUID
    let receiverId: UUID
    let type: String
    let title: String
    let message: String
    /// Heterogeneous JSON payload. Was `[String: Double]?`, which threw a type
    /// mismatch on low_battery / stale_heartbeat alerts that carry a string
    /// `last_seen_at` — and because the dashboard decodes the whole alerts array
    /// at once, one such alert blanked the entire list (US-IOS079). Now decoded
    /// as `[String: JSONValue]?` and forgiving: a malformed payload falls back to
    /// nil instead of throwing.
    let data: [String: JSONValue]?
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyId = try c.decode(UUID.self, forKey: .familyId)
        receiverId = try c.decode(UUID.self, forKey: .receiverId)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        message = try c.decode(String.self, forKey: .message)
        // Forgiving: never let an unexpected `data` shape throw and blank the
        // whole alerts list.
        data = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .data)) ?? nil
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        acknowledgedBy = try c.decodeIfPresent(UUID.self, forKey: .acknowledgedBy)
        acknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        acknowledgedByName = try c.decodeIfPresent(String.self, forKey: .acknowledgedByName)
    }
}
