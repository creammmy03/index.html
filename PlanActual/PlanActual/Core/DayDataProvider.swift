import Foundation
import SwiftData

/// 하루 하나를 계산한 결과
struct DayResult {
    let day: Date
    let clock: DayClock
    let range: DateInterval
    let items: [PlanItem]
    let spans: [ActualSpan]
    let analysis: DayAnalysis
}

/// 뷰 밖(알림 · 위젯 · 인사이트 · 목표)에서 하루를 계산할 때 써요.
@MainActor
struct DayDataProvider {
    let ctx: ModelContext
    let calendar: CalendarService

    var prefs: AppPreferences { DataStore.preferences(ctx) }
    var clock: DayClock { DayClock(prefs) }

    func timetables() -> [Timetable] {
        (try? ctx.fetch(FetchDescriptor<Timetable>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func links() -> [CalendarLink] {
        (try? ctx.fetch(FetchDescriptor<CalendarLink>())) ?? []
    }

    func categories() -> [ActivityCategory] {
        (try? ctx.fetch(FetchDescriptor<ActivityCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func items(for day: Date, now: Date = Date()) -> [PlanItem] {
        let c = DataStore.clock(for: day, current: clock, ctx: ctx)
        let range = c.range(for: day)
        let events = prefs.showCalendarEvents ? calendar.events(in: range) : []
        return PlanResolver.items(day: day, clock: c, blocks: DataStore.plans(in: range, ctx: ctx),
                                  timetables: timetables(), events: events, links: links(), now: now)
    }

    func result(for day: Date, now: Date = Date()) -> DayResult {
        results(for: [day], now: now)[0]
    }

    /// 여러 날을 한 번에 — 가져오기는 한 번만 해요.
    func results(for days: [Date], now: Date = Date()) -> [DayResult] {
        guard let first = days.min(), let last = days.max() else { return [] }
        let current = clock
        let p = prefs
        let span = DateInterval(start: current.range(for: first).start.addingTimeInterval(-86400),
                                end: current.range(for: last).end.addingTimeInterval(86400))
        let blocks = DataStore.plans(in: span, ctx: ctx)
        let actuals = DataStore.actuals(in: span, ctx: ctx)
        let events = p.showCalendarEvents ? calendar.events(in: span) : []
        let tts = timetables(), lnks = links()
        let includeArchived = p.includeArchivedInStats
        return days.map { day in
            let c = DataStore.clock(for: day, current: current, ctx: ctx)
            let range = c.range(for: day)
            let items = PlanResolver.items(day: day, clock: c,
                                           blocks: blocks.filter { $0.end > range.start && $0.start < range.end },
                                           timetables: tts,
                                           events: events.filter { $0.end > range.start && $0.start < range.end },
                                           links: lnks, now: now)
            let records = includeArchived ? actuals : actuals.filter { !($0.detail?.isArchived ?? false) }
            let spans = ActualSpan.make(records, in: range, now: now)
            let analysis = MatchEngine.analyze(range: range, items: items, actuals: spans, now: now)
            return DayResult(day: day, clock: c, range: range, items: items, spans: spans, analysis: analysis)
        }
    }
}
