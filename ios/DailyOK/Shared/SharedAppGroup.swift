import Foundation

/// Constants for the App Group shared between the main app, the notification
/// service extension, the widget/control extension, and (via WatchConnectivity)
/// the watch app. This is the single hand-off point for the lightweight
/// check-in snapshot that out-of-process surfaces read and write.
///
/// NOTE: `group.com.wellvo.ios` must be enabled as an App Group capability on
/// every target that links these files (app + extensions + watch). The main
/// app already writes to this suite in `SupabaseService`.
enum SharedAppGroup {
    static let identifier = "group.com.wellvo.ios"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    enum Key {
        /// Encoded `SharedCheckInState`.
        static let checkInState = "shared_checkin_state"
    }
}
