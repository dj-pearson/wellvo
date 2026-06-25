import WidgetKit
import SwiftUI
import AppIntents

/// iOS 18 Control Center control (also assignable to the Action Button) that
/// fires the shared `CheckInIntent`. One press to check in from anywhere.
@available(iOS 18.0, *)
struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.wellvo.ios.checkin.control") {
            ControlWidgetButton(action: CheckInIntent(source: "control")) {
                Label("Check In", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Daily OK Check-In")
        .description("Let your family know you're OK.")
    }
}
