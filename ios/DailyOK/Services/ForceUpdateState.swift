import SwiftUI

/// Global, app-wide "this build is too old" state. `ContentView` shows a
/// blocking update screen while `required` is true — the backend has declared
/// this build below `MIN_SUPPORTED_IOS_APP_VERSION`, so continuing would risk
/// hitting an API contract this build no longer satisfies.
///
/// Two ways in:
/// - `refreshFromServer()` reads GET `/app-config` at launch and on every
///   foreground (throttled). Most of the app talks to PostgREST directly, so
///   without this a retired build could run for days without ever making an
///   edge call that could answer 426.
/// - `EdgeFunctionsClient` latches it on any 426 `update_required` response.
///
/// A 426 is never undone within the process. A later `/app-config` that says
/// this build is at or above the floor does clear it, so an operator who
/// raised the floor by mistake and lowered it again doesn't leave phones stuck
/// until they are force-quit.
@MainActor
final class ForceUpdateState: ObservableObject {
    static let shared = ForceUpdateState()

    @Published private(set) var required = false
    /// App Store URL supplied by the server, or the bundled fallback.
    @Published private(set) var updateURLString: String = Configuration.appStoreURL

    /// Set by a 426; `/app-config` never clears it.
    private var latchedByServerRejection = false
    private var lastConfigCheck: Date?
    private static let configCheckInterval: TimeInterval = 300

    private init() {}

    /// A 426 from an edge endpoint.
    func trigger(updateURLString: String?) {
        latchedByServerRejection = true
        apply(required: true, updateURLString: updateURLString)
    }

    var updateURL: URL? { URL(string: updateURLString) }

    // MARK: - /app-config

    /// Body of GET `<edge>/app-config` (edge-functions/shared/config.ts
    /// `appConfigPayload`). Every field optional: unknown or missing keys must
    /// never block the app.
    struct AppConfig: Decodable, Equatable {
        let min_ios_version: String?
        let min_android_version: String?
        let update_url_ios: String?
        let update_url_android: String?
    }

    /// Ask the server for the current floor and block if this build is below
    /// it. Fails open: offline, a pin failure, a server without the route
    /// (404) or an unreadable body all leave the app running — the 426 path
    /// still backs this up on the next edge call.
    func refreshFromServer(force: Bool = false) async {
        if !force, let lastConfigCheck,
           Date().timeIntervalSince(lastConfigCheck) < Self.configCheckInterval {
            return
        }
        lastConfigCheck = Date()
        guard let config = await Self.fetchAppConfig() else { return }
        let below = Self.isBelowMinimum(current: Configuration.appVersion, minimum: config.min_ios_version)
        if below {
            apply(required: true, updateURLString: config.update_url_ios)
        } else if !latchedByServerRejection {
            apply(required: false, updateURLString: config.update_url_ios)
        }
    }

    private func apply(required: Bool, updateURLString: String?) {
        if let updateURLString, !updateURLString.isEmpty {
            self.updateURLString = updateURLString
        }
        if self.required != required { self.required = required }
    }

    nonisolated private static func fetchAppConfig() async -> AppConfig? {
        guard let url = URL(string: "\(Configuration.edgeFunctionsURL)/app-config") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(Configuration.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue("ios", forHTTPHeaderField: "X-App-Platform")
        do {
            let (data, response) = try await PinnedURLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Version comparison (mirrors edge-functions/shared/config.ts)

    /// Dotted numeric compare: "1.0.10" > "1.0.9"; missing segments are 0
    /// ("1.0" == "1.0.0"); a segment counts by its leading digits (0 if none) so
    /// a malformed string never throws. Negative when a < b.
    nonisolated static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".", omittingEmptySubsequences: false)
        let pb = b.split(separator: ".", omittingEmptySubsequences: false)
        for i in 0..<max(pa.count, pb.count) {
            let na = i < pa.count ? leadingNumber(pa[i]) : 0
            let nb = i < pb.count ? leadingNumber(pb[i]) : 0
            if na != nb { return na < nb ? -1 : 1 }
        }
        return 0
    }

    /// Leading digits of a segment, like JavaScript parseInt ("0-beta" -> 0,
    /// "10rc" -> 10); none -> 0.
    nonisolated private static func leadingNumber(_ segment: Substring) -> Int {
        Int(String(segment.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isASCII && $0.isNumber }))) ?? 0
    }

    /// True only for a real floor ("0.0.0", empty or nil means none) that
    /// `current` is strictly below.
    nonisolated static func isBelowMinimum(current: String, minimum: String?) -> Bool {
        guard let minimum = minimum?.trimmingCharacters(in: .whitespaces), !minimum.isEmpty,
              compareVersions(minimum, "0.0.0") > 0 else { return false }
        return compareVersions(current, minimum) < 0
    }
}
