import SwiftUI

@main
struct DailyOKWatchApp: App {
    init() {
        // Start listening for the session snapshot the iPhone pushes over
        // WatchConnectivity so the watch can check in on its own.
        WatchConnectivityProvider.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchCheckInView()
        }
    }
}
