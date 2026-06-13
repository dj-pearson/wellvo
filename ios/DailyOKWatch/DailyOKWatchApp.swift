import SwiftUI

@main
struct DailyOKWatchApp: App {
    init() {
        // Start listening for the session snapshot the iPhone pushes over
        // WatchConnectivity so the watch can check in on its own.
        WatchConnectivityProvider.shared.activate()
        // Handle the check-in reminder's action buttons on the wrist.
        WatchNotificationController.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchCheckInView()
        }
        WKNotificationScene(controller: CheckInNotificationController.self, category: "CHECKIN_REQUEST")
    }
}
