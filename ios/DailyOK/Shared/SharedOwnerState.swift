import Foundation

/// Glanceable owner snapshot published to the shared App Group so the owner
/// status widget can render every receiver's check-in state without a network
/// round-trip or a live app session.
struct SharedOwnerReceiver: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// "checked_in" | "pending" | "missed" | "no_data"
    var status: String
    var lastCheckInAt: Date?
}

struct SharedOwnerState: Codable, Equatable {
    var receivers: [SharedOwnerReceiver]
    var updatedAt: Date

    var total: Int { receivers.count }
    var checkedInCount: Int { receivers.filter { $0.status == "checked_in" }.count }

    /// The receiver an owner most wants to see first: a missed one, else a
    /// pending one, else the first.
    var mostRelevant: SharedOwnerReceiver? {
        receivers.first(where: { $0.status == "missed" })
            ?? receivers.first(where: { $0.status == "pending" })
            ?? receivers.first
    }
}

enum SharedOwnerStore {
    private static let key = "shared_owner_state"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    static func load() -> SharedOwnerState? {
        guard let data = SharedAppGroup.defaults?.data(forKey: key) else { return nil }
        return try? decoder.decode(SharedOwnerState.self, from: data)
    }

    static func save(_ state: SharedOwnerState) {
        guard let data = try? encoder.encode(state) else { return }
        SharedAppGroup.defaults?.set(data, forKey: key)
    }

    static func clear() {
        SharedAppGroup.defaults?.removeObject(forKey: key)
    }
}
