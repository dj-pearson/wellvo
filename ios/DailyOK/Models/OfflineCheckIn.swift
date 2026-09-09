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
    /// Which scheduled window this check-in answers, as "HH:mm" (US-IOS048).
    /// `nil` means day-level, which is correct for the single-window schedules
    /// that are the common case — and is what every row written before
    /// US-IOS137 carries, so SwiftData's lightweight migration adds this as a
    /// new optional attribute and existing queued rows keep their old meaning.
    var slotKey: String?

    init(
        id: UUID = UUID(),
        familyId: UUID,
        receiverId: UUID,
        mood: Mood? = nil,
        source: CheckInSource = .app,
        createdAt: Date = Date(),
        synced: Bool = false,
        slotKey: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.receiverId = receiverId
        self.mood = mood?.rawValue
        self.source = source.rawValue
        self.createdAt = createdAt
        self.synced = synced
        self.slotKey = slotKey
    }
}
