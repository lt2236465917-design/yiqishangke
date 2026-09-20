import WidgetKit
import SwiftUI

@main
struct ScheduleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        RemainingTodayWidget()
    }
}
