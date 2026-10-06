import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// 앱 전체에서 하나만 쓰는 저장소 · 서비스.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let router = AppRouter()
    let toasts = ToastCenter()
    let calendar = CalendarService()
    let health = HealthService()
    let sync = SyncMonitor()

    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var context: ModelContext { container.mainContext }
    var provider: DayDataProvider { DayDataProvider(ctx: context, calendar: calendar) }

    private init() {
        container = PersistenceController.makeContainer()
        container.mainContext.autosaveEnabled = true
        DataStore.seedIfNeeded(container.mainContext)
        DataStore.dedupe(container.mainContext)

        observers.append(NotificationCenter.default.addObserver(forName: .pendingTimerStop, object: nil, queue: .main) { _ in
            Task { @MainActor in AppServices.shared.applyPendingTimerStop() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in AppServices.shared.dataDidChange() }
        })
        sync.onImport = { [weak self] in
            guard let self else { return }
            DataStore.dedupe(self.context)
            self.dataDidChange()
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            calendar.refreshStatus()
            applyPendingTimerStop()
            toasts.resume()
            dataDidChange()
        case .background:
            toasts.pause()
            refreshTask?.cancel()
            Task { await refreshSystemSurfaces() }
        default:
            break
        }
    }

    /// 저장할 때마다 알림 · 위젯 · 라이브 액티비티를 다시 맞춰요 (0.8초 모아서).
    func dataDidChange() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.refreshSystemSurfaces()
        }
    }

    func refreshSystemSurfaces() async {
        let now = Date()
        let p = provider
        WidgetBridge.publish(provider: p, now: now)
        let running = DataStore.runningRecords(context).last
        let today = p.clock.logicalDay(for: now)
        let current = p.items(for: today, now: now).first { $0.start <= now && $0.end > now }
        LiveActivityService.sync(running: running, plan: current)
        await NotificationService.reschedule(provider: p, now: now)
    }

    /// 라이브 액티비티 정지 버튼이 남긴 종료 시각을 반영해요.
    func applyPendingTimerStop() {
        let defaults = SharedConfig.defaults
        let ts = defaults.double(forKey: SharedConfig.pendingTimerStopKey)
        guard ts > 0 else { return }
        defaults.removeObject(forKey: SharedConfig.pendingTimerStopKey)
        let at = Date(timeIntervalSince1970: ts)
        for r in DataStore.runningRecords(context) where r.start < at {
            DataStore.stopTimer(r, at: at, ctx: context)
        }
    }

    func handleNotification(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        if kind == "dayclose" {
            router.tab = .today
            router.showDayClose = true
            return
        }
        guard kind == "confirm" else { return }
        switch response.actionIdentifier {
        case "DONE": DataStore.confirmFromNotification(userInfo: info, kind: .done, ctx: context)
        case "PARTIAL": DataStore.confirmFromNotification(userInfo: info, kind: .partial, ctx: context)
        case "SKIP": DataStore.confirmFromNotification(userInfo: info, kind: .skip, ctx: context)
        default:
            router.tab = .today
            router.pendingConfirmKey = info["key"] as? String
        }
    }
}
