import ActivityKit
import AppIntents
import Foundation

/// 기록 중 타이머의 라이브 액티비티 (잠금화면 · 다이내믹 아일랜드).
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var planTitle: String?
        var planStart: Date?
        var planEnd: Date?
        var matchesPlan: Bool
    }

    var title: String
    var categoryName: String
    var colorHex: String
}

/// 라이브 액티비티의 정지 버튼. 앱을 열지 않고 처리해요.
/// 기록 종료 시각을 공유 저장소에 남기고, 앱이 살아 있으면 바로 반영해요.
struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "타이머 정지"
    static let description = IntentDescription("기록 중인 타이머를 멈춰요.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedConfig.defaults.set(Date().timeIntervalSince1970, forKey: SharedConfig.pendingTimerStopKey)
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .pendingTimerStop, object: nil)
        }
        return .result()
    }
}
