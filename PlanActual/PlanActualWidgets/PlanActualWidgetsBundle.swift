import SwiftUI
import WidgetKit

@main
struct PlanActualWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayMatchWidget()
        MatchGaugeWidget()
        TimerLiveActivityWidget()
    }
}
