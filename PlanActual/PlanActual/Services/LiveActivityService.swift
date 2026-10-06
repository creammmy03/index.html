import ActivityKit
import Foundation

/// 기록 중 타이머를 잠금화면 · 다이내믹 아일랜드에 띄워요. 시작한 기기에만 떠요.
@MainActor
enum LiveActivityService {
    static func sync(running: ActualRecord?, plan: PlanItem?) {
        let current = Activity<TimerActivityAttributes>.activities
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let r = running,
              r.deviceName == nil || r.deviceName == DataStore.deviceName else {
            endAll()
            return
        }
        let attrs = TimerActivityAttributes(
            title: r.detail?.fullName ?? "기록 중",
            categoryName: r.detail?.category?.name ?? "",
            colorHex: r.detail?.colorHex ?? "#52606F"
        )
        let matches = plan?.categoryID != nil && plan?.categoryID == r.detail?.category?.id
        let state = TimerActivityAttributes.ContentState(
            startDate: r.start, planTitle: plan?.title, planStart: plan?.start, planEnd: plan?.end, matchesPlan: matches
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if let existing = current.first(where: { $0.attributes.title == attrs.title && $0.content.state.startDate == r.start }) {
            Task { await existing.update(content) }
            for other in current where other.id != existing.id {
                Task { await other.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            for a in current { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            _ = try? Activity<TimerActivityAttributes>.request(attributes: attrs, content: content, pushType: nil)
        }
    }

    static func endAll() {
        for a in Activity<TimerActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
