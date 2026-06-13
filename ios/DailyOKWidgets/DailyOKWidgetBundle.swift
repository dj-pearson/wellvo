import WidgetKit
import SwiftUI

@main
struct DailyOKWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheckInWidget()
        if #available(iOS 18.0, *) {
            CheckInControl()
        }
    }
}
