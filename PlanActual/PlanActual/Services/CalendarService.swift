import EventKit
import Foundation
import Observation
import UIKit

/// EventKit에서 읽은 일정 하나 (기기마다 다른 ID 대신 external ID로 맞춰요).
struct CalendarEventInfo: Identifiable, Hashable {
    var id: String { "\(externalID)|\(start.timeIntervalSince1970)" }
    let eventIdentifier: String
    let externalID: String
    let title: String
    let start: Date
    let end: Date
    let calendarKey: String
    let calendarTitle: String
    let calendarColorHex: String
    let isRecurring: Bool
    let location: String?
}

@MainActor
@Observable
final class CalendarService {
    @ObservationIgnored let store = EKEventStore()

    private(set) var eventStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var reminderStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    /// EKEventStoreChanged를 받을 때마다 올라가요 — 뷰가 다시 읽게 해요.
    private(set) var revision = 0
    private(set) var lastChange = Date()

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.revision += 1
                self?.lastChange = Date()
            }
        }
    }

    var hasEventAccess: Bool { eventStatus == .fullAccess }
    var hasReminderAccess: Bool { reminderStatus == .fullAccess }
    var eventAccessDenied: Bool { eventStatus == .denied || eventStatus == .restricted || eventStatus == .writeOnly }
    var reminderAccessDenied: Bool { reminderStatus == .denied || reminderStatus == .restricted || reminderStatus == .writeOnly }

    func refreshStatus() {
        eventStatus = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    @discardableResult
    func requestEventAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        refreshStatus()
        revision += 1
        return granted
    }

    @discardableResult
    func requestReminderAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        refreshStatus()
        revision += 1
        return granted
    }

    // MARK: 캘린더

    nonisolated static func key(for calendar: EKCalendar) -> String {
        "\(calendar.source?.sourceType.rawValue ?? -1)|\(calendar.title)"
    }

    nonisolated static func accountName(for calendar: EKCalendar) -> String {
        guard let source = calendar.source else { return "" }
        switch source.sourceType {
        case .local: return "이 기기"
        case .calDAV: return source.title.isEmpty ? "CalDAV" : source.title
        case .exchange: return "Exchange"
        case .subscribed: return "구독"
        case .birthdays: return "생일"
        default: return source.title
        }
    }

    func eventCalendars() -> [EKCalendar] {
        _ = revision
        guard hasEventAccess else { return [] }
        return store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    func writableCalendars() -> [EKCalendar] {
        eventCalendars().filter { $0.allowsContentModifications }
    }

    func calendar(forKey key: String) -> EKCalendar? {
        eventCalendars().first { Self.key(for: $0) == key }
    }

    func events(in interval: DateInterval) -> [CalendarEventInfo] {
        _ = revision
        guard hasEventAccess, interval.duration > 0 else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map(Self.info(from:))
            .sorted { $0.start < $1.start }
    }

    nonisolated static func info(from e: EKEvent) -> CalendarEventInfo {
        let cal = e.calendar
        let hex: String = {
            guard let cg = cal?.cgColor, let comps = cg.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, comps.count >= 3 else {
                return "#8A8A85"
            }
            return RGB(r: comps[0] * 255, g: comps[1] * 255, b: comps[2] * 255).hex
        }()
        return CalendarEventInfo(
            eventIdentifier: e.eventIdentifier ?? "",
            externalID: e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString,
            title: e.title ?? "제목 없음",
            start: e.startDate,
            end: e.endDate,
            calendarKey: cal.map(Self.key(for:)) ?? "",
            calendarTitle: cal?.title ?? "",
            calendarColorHex: hex,
            isRecurring: e.hasRecurrenceRules,
            location: e.location
        )
    }

    /// 반복 일정이면 같은 식별자로 여러 번 나오니 시작 시각으로 그 회차를 찾아요.
    func event(for info: CalendarEventInfo) -> EKEvent? {
        guard hasEventAccess else { return nil }
        let window = DateInterval(start: info.start.addingTimeInterval(-60), end: info.end.addingTimeInterval(60))
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let matches = store.events(matching: predicate)
        return matches.first { $0.calendarItemExternalIdentifier == info.externalID && abs($0.startDate.timeIntervalSince(info.start)) < 61 }
            ?? store.event(withIdentifier: info.eventIdentifier)
    }

    func save(_ event: EKEvent, span: EKSpan) throws {
        try store.save(event, span: span, commit: true)
        revision += 1
    }

    func remove(_ event: EKEvent, span: EKSpan) throws {
        try store.remove(event, span: span, commit: true)
        revision += 1
    }

    func newEvent() -> EKEvent { EKEvent(eventStore: store) }

    // MARK: 미리알림

    func reminderLists() -> [EKCalendar] {
        _ = revision
        guard hasReminderAccess else { return [] }
        return store.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    func fetchReminders(lists: [EKCalendar]?, completed: Bool) async -> [EKReminder] {
        guard hasReminderAccess else { return [] }
        let predicate: NSPredicate
        if completed {
            let since = Date().addingTimeInterval(-14 * 86400)
            predicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: Date(), calendars: lists)
        } else {
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        }
        let store = self.store
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func setCompleted(_ reminder: EKReminder, _ done: Bool) throws {
        reminder.isCompleted = done
        try store.save(reminder, commit: true)
        revision += 1
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
