import Foundation

/// 앱과 위젯 확장이 함께 쓰는 설정값.
enum SharedConfig {
    static let appGroupID: String = {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.example.planactual"
    }()

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static let pendingTimerStopKey = "pendingTimerStop"
    static let widgetSnapshotKey = "widgetSnapshot"
    static let urlScheme = "planactual"
}

extension Notification.Name {
    /// 라이브 액티비티의 정지 버튼이 눌렸을 때 앱 안에서 바로 처리하기 위한 알림.
    static let pendingTimerStop = Notification.Name("PlanActual.pendingTimerStop")
}
