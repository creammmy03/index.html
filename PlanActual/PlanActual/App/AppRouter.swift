import Foundation
import Observation

enum AppTab: Hashable {
    case today, plan, goals, insights, settings
}

/// 탭 · 알림 · 위젯에서 들어오는 이동을 모아요.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .today
    /// 알림 본문을 눌렀을 때 01의 확인 시트를 열 계획 키
    var pendingConfirmKey: String?
    var showDayClose = false
    /// 계획 탭을 특정 날짜로 열기
    var planJumpDate: Date?

    func handle(url: URL) {
        guard url.scheme == SharedConfig.urlScheme else { return }
        switch url.host {
        case "summary":
            tab = .today
            showDayClose = true
        case "confirm":
            tab = .today
            let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "key" }?.value
            pendingConfirmKey = key
        case "plan":
            tab = .plan
        default:
            tab = .today
        }
    }

    func openPlan(on day: Date) {
        planJumpDate = day
        tab = .plan
    }
}
