import Foundation
import WatchKit
import WidgetKit

@MainActor
final class WatchCheckInModel: ObservableObject {
    @Published var state: SharedCheckInState?
    @Published var isCheckingIn = false
    @Published var didCheckIn = false
    @Published var errorMessage: String?

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        reload()
    }

    var isSignedIn: Bool { state != nil }

    func reload() {
        state = SharedCheckInStore.load()
        didCheckIn = state?.hasCheckedInToday ?? false
    }

    func checkIn() async {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        errorMessage = nil

        let rawBattery = WKInterfaceDevice.current().batteryLevel
        let battery: Double? = rawBattery >= 0 ? Double(rawBattery) : nil

        do {
            let updated = try await SharedCheckInClient.checkIn(source: "watch", batteryLevel: battery)
            state = updated
            didCheckIn = true
            WKInterfaceDevice.current().play(.success)
            WidgetCenter.shared.reloadAllTimelines() // refresh the complication
            WatchConnectivityProvider.shared.notifyPhoneOfCheckIn()
        } catch {
            errorMessage = (error as? SharedCheckInError)?.localizedDescription
                ?? "Couldn't check in. Please try again."
            WKInterfaceDevice.current().play(.failure)
        }

        isCheckingIn = false
    }
}
