import Foundation
import SwiftData

/// Stores check-ins locally when the device is offline.
/// Queued check-ins are synced to Supabase when connectivity returns.
@Model
final class OfflineCheckIn {
    @Attribute(.unique) var id: UUID
    var familyId: UUID
    var receiverId: UUID
    var mood: String? // Raw Mood value
    var source: String // Raw CheckInSource value
    var createdAt: Date
    var synced: Bool

    init(
        id: UUID = UUID(),
        familyId: UUID,
        receiverId: UUID,
        mood: Mood? = nil,
        source: CheckInSource = .app,
        createdAt: Date = Date(),
        synced: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.receiverId = receiverId
        self.mood = mood?.rawValue
        self.source = source.rawValue
        self.createdAt = createdAt
        self.synced = synced
    }
}
