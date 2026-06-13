import WidgetKit
import SwiftUI

@main
struct DailyOKWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheckInWidget()
        OwnerStatusWidget()
        if #available(iOS 18.0, *) {
            CheckInControl()
        }
    }
}
