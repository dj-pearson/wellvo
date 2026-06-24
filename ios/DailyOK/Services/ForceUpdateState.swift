import SwiftUI

/// Global, app-wide "this build is too old" state. Set when an edge endpoint
/// responds with a 426 force-update payload (see `EdgeFunctionsClient`). Once
/// set, `ContentView` shows a blocking update screen — the backend has declared
/// this build below `MIN_SUPPORTED_IOS_APP_VERSION`, so continuing would risk
/// hitting an API contract this build no longer satisfies.
///
/// One-way latch: it never clears itself within a session (the only fix is to
/// update), so a single 426 reliably blocks the app even if later calls fail
/// for other reasons.
@MainActor
final class ForceUpdateState: ObservableObject {
    static let shared = ForceUpdateState()

    @Published private(set) var required = false
    /// App Store URL supplied by the server, or the bundled fallback.
    @Published private(set) var updateURLString: String = Configuration.appStoreURL

    private init() {}

    func trigger(updateURLString: String?) {
        if let updateURLString, !updateURLString.isEmpty {
            self.updateURLString = updateURLString
        }
        required = true
    }

    var updateURL: URL? { URL(string: updateURLString) }
}
