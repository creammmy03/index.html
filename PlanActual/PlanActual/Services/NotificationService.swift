import Foundation
import UserNotifications

/// 끝난 계획 확인 알림(액션 3개)과 하루 마감 알림.
@MainActor
enum NotificationService {
    static let confirmCategory = "PLAN_CONFIRM"
    static let closeCategory = "DAY_CLOSE"

    static func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: "했어요", options: [])
        let partial = UNNotificationAction(identifier: "PARTIAL", title: "일부만", options: [])
        let skip = UNNotificationAction(identifier: "SKIP", title: "안 했어요", options: [])
        let confirm = UNNotificationCategory(identifier: confirmCategory, actions: [done, partial, skip], intentIdentifiers: [], options: [])
        let close = UNNotificationCategory(identifier: closeCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([confirm, close])
    }

    /// 첫 계획을 저장한 직후에 물어요.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func reschedule(provider: DayDataProvider, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional, .ephemeral]
        guard allowed.contains(settings.authorizationStatus) else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("confirm|") || $0.hasPrefix("dayclose|") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let prefs = provider.prefs
        let today = provider.clock.logicalDay(for: now)
        var requests: [UNNotificationRequest] = []
        for day in [today, DayClock.addDays(1, to: today)] {
            if prefs.askWhenDone {
                for item in provider.items(for: day, now: now) where item.askWhenDone && item.confirmation == nil && item.end > now {
                    requests.append(confirmRequest(for: item, now: now))
                }
            }
            if prefs.closeReminderOffset > 0 {
                let range = provider.clock.range(for: day)
                let fire = range.end.addingTimeInterval(-Double(prefs.closeReminderOffset) * 60)
                if fire > now {
                    let content = UNMutableNotificationContent()
                    content.title = "하루 마감할 시간이에요"
                    content.body = "\(Fmt.dayTitle(day)) · 계획과 실제를 맞춰보고 한 줄 남겨요."
                    content.categoryIdentifier = closeCategory
                    content.userInfo = ["kind": "dayclose", "dayKey": DayClock.dayKey(day)]
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
                    requests.append(UNNotificationRequest(identifier: "dayclose|\(DayClock.dayKey(day))", content: content, trigger: trigger))
                }
            }
        }
        requests.sort { fireDate($0) < fireDate($1) }
        for r in requests.prefix(60) {
            try? await center.add(r)
        }
    }

    private static func fireDate(_ r: UNNotificationRequest) -> Double {
        (r.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? .greatestFiniteMagnitude
    }

    static func confirmRequest(for item: PlanItem, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(item.title) 끝났어요"
        content.body = "\(Fmt.range(item.start, item.end)) 계획 · 했나요?"
        content.sound = .default
        content.categoryIdentifier = confirmCategory
        var info: [String: Any] = [
            "kind": "confirm",
            "key": item.key,
            "dayKey": item.dayKey,
            "start": item.start.timeIntervalSince1970,
            "end": item.end.timeIntervalSince1970,
            "title": item.event?.title ?? item.title
        ]
        if let b = item.block { info["blockID"] = b.id.uuidString }
        if let d = item.detail { info["detailID"] = d.id.uuidString }
        if let s = item.slot { info["slotKey"] = "\(item.dayKey)|\(s.id.uuidString)" }
        if let e = item.event { info["externalID"] = e.externalID }
        switch item.kind {
        case .calendar: info["source"] = PlanSource.calendar.rawValue
        case .timetable: info["source"] = PlanSource.timetable.rawValue
        case .todo: info["source"] = PlanSource.todo.rawValue
        case .manual: info["source"] = PlanSource.manual.rawValue
        }
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.end.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: "confirm|\(item.key)", content: content, trigger: trigger)
    }
}
