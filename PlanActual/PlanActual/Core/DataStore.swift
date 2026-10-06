import Foundation
import SwiftData
import UIKit

/// 모델을 만들고 고치는 작업 모음. 관계는 항상 insert 뒤에 연결해요.
@MainActor
enum DataStore {
    static func save(_ ctx: ModelContext) {
        do { try ctx.save() } catch { print("저장 실패: \(error)") }
    }

    static var deviceName: String { UIDevice.current.name }

    // MARK: 만들기

    static func preferences(_ ctx: ModelContext) -> AppPreferences {
        let d = FetchDescriptor<AppPreferences>(sortBy: [SortDescriptor(\.createdAt)])
        if let p = (try? ctx.fetch(d))?.first { return p }
        let p = AppPreferences()
        ctx.insert(p)
        return p
    }

    @discardableResult
    static func makeDetail(name: String, in category: ActivityCategory, ctx: ModelContext, seedKey: String? = nil) -> ActivityDetail {
        let order = (category.details ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let d = ActivityDetail(name: name, sortOrder: order, seedKey: seedKey)
        ctx.insert(d)
        d.category = category
        return d
    }

    @discardableResult
    static func makeCategory(name: String, colorHex: String, ctx: ModelContext) -> ActivityCategory {
        let all = (try? ctx.fetch(FetchDescriptor<ActivityCategory>())) ?? []
        let order = (all.map(\.sortOrder).max() ?? -1) + 1
        let c = ActivityCategory(name: name, colorHex: colorHex, themeID: ColorThemes.themeID(containing: colorHex), sortOrder: order)
        ctx.insert(c)
        return c
    }

    @discardableResult
    static func makePlan(detail: ActivityDetail?, start: Date, end: Date, source: PlanSource, dayKey: String, ctx: ModelContext) -> PlanBlock {
        let b = PlanBlock(start: start, end: end, source: source, dayKey: dayKey)
        ctx.insert(b)
        b.detail = detail
        return b
    }

    @discardableResult
    static func makeActual(detail: ActivityDetail?, start: Date, end: Date?, source: ActualSource, ctx: ModelContext) -> ActualRecord {
        let r = ActualRecord(start: start, end: end, source: source)
        ctx.insert(r)
        r.detail = detail
        return r
    }

    @discardableResult
    static func makeSlot(in timetable: Timetable, detail: ActivityDetail?, weekday: Int, startMinute: Int, endMinute: Int, place: String?, ctx: ModelContext) -> TimetableSlot {
        let s = TimetableSlot(weekday: weekday, startMinute: startMinute, endMinute: endMinute, place: place)
        ctx.insert(s)
        s.timetable = timetable
        s.detail = detail
        timetable.updatedAt = Date()
        return s
    }

    // MARK: 첫 실행

    static func seedIfNeeded(_ ctx: ModelContext) {
        _ = preferences(ctx)
        let count = (try? ctx.fetchCount(FetchDescriptor<ActivityCategory>())) ?? 0
        guard count == 0 else { save(ctx); return }
        let seeds: [(String, String, String, [String])] = [
            ("work", "업무", "#3B66BE", ["기획서 작성", "회의 · 리뷰", "메일 정리"]),
            ("study", "공부", "#23786F", ["영어", "학원 수업", "독서"]),
            ("move", "운동", "#A83E74", ["러닝", "헬스", "산책"]),
            ("rest", "휴식", "#7048BC", ["식사", "개인 시간", "개인 약속"]),
            ("sleep", "수면", "#52606F", ["밤잠"])
        ]
        for (i, s) in seeds.enumerated() {
            let c = ActivityCategory(name: s.1, colorHex: s.2, themeID: "basic", sortOrder: i, seedKey: s.0)
            ctx.insert(c)
            for (j, name) in s.3.enumerated() {
                let d = ActivityDetail(name: name, sortOrder: j, seedKey: "\(s.0).\(j)")
                ctx.insert(d)
                d.category = c
            }
        }
        save(ctx)
    }

    /// 두 기기에서 따로 만든 기본 데이터·설정·시간표 칸을 하나로 합쳐요.
    static func dedupe(_ ctx: ModelContext) {
        var changed = false
        let prefs = (try? ctx.fetch(FetchDescriptor<AppPreferences>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for extra in prefs.dropFirst() { ctx.delete(extra); changed = true }

        let cats = (try? ctx.fetch(FetchDescriptor<ActivityCategory>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var keepers: [String: ActivityCategory] = [:]
        for c in cats {
            guard let key = c.seedKey else { continue }
            guard let keeper = keepers[key] else { keepers[key] = c; continue }
            for d in c.details ?? [] {
                if let twin = (keeper.details ?? []).first(where: { ($0.seedKey != nil && $0.seedKey == d.seedKey) || $0.name == d.name }) {
                    reassign(from: d, to: twin)
                    ctx.delete(d)
                } else {
                    d.category = keeper
                }
            }
            for g in c.goals ?? [] { g.category = keeper }
            ctx.delete(c)
            changed = true
        }

        let ttBlocks = (try? ctx.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate<PlanBlock> { $0.slotKey != nil }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var seen: [String: PlanBlock] = [:]
        for b in ttBlocks {
            guard let k = b.slotKey else { continue }
            if let keep = seen[k] {
                if keep.confirmation == nil, let c = b.confirmation { keep.confirmation = c }
                for a in b.actuals ?? [] { a.planBlock = keep }
                ctx.delete(b)
                changed = true
            } else {
                seen[k] = b
            }
        }
        if changed { save(ctx) }
    }

    /// 세부내역에 걸린 기록 · 계획 · 연결을 다른 세부내역으로 옮겨요.
    static func reassign(from d: ActivityDetail, to target: ActivityDetail) {
        for a in d.actuals ?? [] { a.detail = target; a.updatedAt = Date() }
        for p in d.plans ?? [] { p.detail = target; p.updatedAt = Date() }
        for s in d.slots ?? [] { s.detail = target }
        for l in d.calendarLinks ?? [] { l.detail = target }
        for r in d.reminderLinks ?? [] { r.detail = target }
        for g in d.goals ?? [] { g.detail = target }
    }

    // MARK: 조회

    static func runningRecords(_ ctx: ModelContext) -> [ActualRecord] {
        let d = FetchDescriptor<ActualRecord>(predicate: #Predicate<ActualRecord> { $0.end == nil }, sortBy: [SortDescriptor(\.start)])
        return (try? ctx.fetch(d)) ?? []
    }

    static func plans(in range: DateInterval, ctx: ModelContext) -> [PlanBlock] {
        let s = range.start, e = range.end
        let d = FetchDescriptor<PlanBlock>(predicate: #Predicate<PlanBlock> { $0.start < e && $0.end > s }, sortBy: [SortDescriptor(\.start)])
        return (try? ctx.fetch(d)) ?? []
    }

    static func actuals(in range: DateInterval, ctx: ModelContext) -> [ActualRecord] {
        let s = range.start.addingTimeInterval(-86400), e = range.end
        let d = FetchDescriptor<ActualRecord>(predicate: #Predicate<ActualRecord> { $0.start < e && $0.start > s }, sortBy: [SortDescriptor(\.start)])
        let start = range.start
        return ((try? ctx.fetch(d)) ?? []).filter { ($0.end ?? .distantFuture) > start }
    }

    static func block(id: UUID, ctx: ModelContext) -> PlanBlock? {
        let d = FetchDescriptor<PlanBlock>(predicate: #Predicate<PlanBlock> { $0.id == id })
        return (try? ctx.fetch(d))?.first
    }

    static func detail(id: UUID, ctx: ModelContext) -> ActivityDetail? {
        let d = FetchDescriptor<ActivityDetail>(predicate: #Predicate<ActivityDetail> { $0.id == id })
        return (try? ctx.fetch(d))?.first
    }

    static func summary(dayKey: String, ctx: ModelContext) -> DaySummary? {
        let d = FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.dayKey == dayKey })
        return (try? ctx.fetch(d))?.first
    }

    // MARK: 타이머

    /// 타이머는 한 번에 하나. 이미 기록 중이면 멈추고 새로 시작해요.
    @discardableResult
    static func startTimer(detail: ActivityDetail, at date: Date = Date(), ctx: ModelContext) -> ActualRecord {
        for r in runningRecords(ctx) { finish(r, at: date, ctx: ctx) }
        let r = makeActual(detail: detail, start: date, end: nil, source: .timer, ctx: ctx)
        r.deviceName = deviceName
        save(ctx)
        return r
    }

    static func stopTimer(_ record: ActualRecord, at date: Date = Date(), ctx: ModelContext) {
        finish(record, at: date, ctx: ctx)
        save(ctx)
    }

    private static func finish(_ r: ActualRecord, at date: Date, ctx: ModelContext) {
        let end = max(r.start, date)
        if end.timeIntervalSince(r.start) < 60 {
            ctx.delete(r)
        } else {
            r.end = end
            r.updatedAt = Date()
        }
    }

    // MARK: 계획 확인

    /// 시간표·캘린더 칸은 고치거나 확인할 때 PlanBlock으로 저장해요.
    static func materialize(_ item: PlanItem, ctx: ModelContext) -> PlanBlock {
        if let b = item.block { return b }
        let source: PlanSource
        switch item.kind {
        case .manual: source = .manual
        case .todo: source = .todo
        case .timetable: source = .timetable
        case .calendar: source = .calendar
        }
        let b = makePlan(detail: item.detail, start: item.start, end: item.end, source: source, dayKey: item.dayKey, ctx: ctx)
        if let slot = item.slot { b.slotKey = "\(item.dayKey)|\(slot.id.uuidString)" }
        if let ev = item.event {
            b.ekExternalID = ev.externalID
            b.title = ev.title
        }
        return b
    }

    /// 계획 확인을 기록하고, 되돌리는 함수를 돌려줘요.
    static func confirm(_ block: PlanBlock, as kind: Confirmation, otherDetail: ActivityDetail? = nil, now: Date = Date(), ctx: ModelContext) -> () -> Void {
        let previous = block.confirmation
        block.confirmation = kind
        var created: [ActualRecord] = []
        switch kind {
        case .done:
            created = fillUncovered(start: block.start, end: min(block.end, now), detail: block.detail, plan: block, ctx: ctx)
        case .other:
            created = fillUncovered(start: block.start, end: min(block.end, now), detail: otherDetail, plan: nil, ctx: ctx)
        case .partial, .skip:
            break
        }
        save(ctx)
        return {
            block.confirmation = previous
            for r in created { ctx.delete(r) }
            save(ctx)
        }
    }

    /// 구간 안에서 기록이 비어 있는 부분만 채워요.
    @discardableResult
    static func fillUncovered(start: Date, end: Date, detail: ActivityDetail?, plan: PlanBlock?, source: ActualSource = .confirm, ctx: ModelContext) -> [ActualRecord] {
        guard end.timeIntervalSince(start) >= 60 else { return [] }
        let existing = actuals(in: DateInterval(start: start, end: end), ctx: ctx)
            .map { ($0.start, $0.end ?? Date()) }
            .sorted { $0.0 < $1.0 }
        var cursor = start
        var created: [ActualRecord] = []
        func add(_ s: Date, _ e: Date) {
            guard e.timeIntervalSince(s) >= 60 else { return }
            let r = makeActual(detail: detail, start: s, end: e, source: source, ctx: ctx)
            r.planBlock = plan
            created.append(r)
        }
        for (s, e) in existing {
            if e <= cursor { continue }
            if s >= end { break }
            if s > cursor { add(cursor, min(s, end)) }
            cursor = max(cursor, e)
            if cursor >= end { break }
        }
        if cursor < end { add(cursor, end) }
        return created
    }

    /// 알림 액션에서 온 확인 — 앱을 열지 않고 처리해요.
    static func confirmFromNotification(userInfo: [AnyHashable: Any], kind: Confirmation, ctx: ModelContext) {
        guard let target = block(fromNotification: userInfo, ctx: ctx) else { return }
        _ = confirm(target, as: kind, ctx: ctx)
    }

    static func block(fromNotification info: [AnyHashable: Any], ctx: ModelContext) -> PlanBlock? {
        if let s = info["blockID"] as? String, let id = UUID(uuidString: s), let b = block(id: id, ctx: ctx) {
            return b
        }
        guard let dayKey = info["dayKey"] as? String,
              let startTS = info["start"] as? Double,
              let endTS = info["end"] as? Double else { return nil }
        let start = Date(timeIntervalSince1970: startTS), end = Date(timeIntervalSince1970: endTS)
        let existing = plans(in: DateInterval(start: start, end: end), ctx: ctx)
        if let slotKey = info["slotKey"] as? String, let b = existing.first(where: { $0.slotKey == slotKey }) { return b }
        if let ext = info["externalID"] as? String, let b = existing.first(where: { $0.ekExternalID == ext && $0.dayKey == dayKey }) { return b }
        let detail = (info["detailID"] as? String).flatMap(UUID.init(uuidString:)).flatMap { self.detail(id: $0, ctx: ctx) }
        let kind = PlanSource(rawValue: info["source"] as? String ?? "") ?? .timetable
        let b = makePlan(detail: detail, start: start, end: end, source: kind, dayKey: dayKey, ctx: ctx)
        b.slotKey = info["slotKey"] as? String
        b.ekExternalID = info["externalID"] as? String
        b.title = info["title"] as? String
        return b
    }

    // MARK: 보관 · 삭제

    static func archive(_ d: ActivityDetail) { d.archivedAt = Date(); d.updatedAt = Date() }
    static func restore(_ d: ActivityDetail) { d.archivedAt = nil; d.updatedAt = Date() }
    static func archive(_ c: ActivityCategory) { c.archivedAt = Date(); c.updatedAt = Date() }
    static func restore(_ c: ActivityCategory) { c.archivedAt = nil; c.updatedAt = Date() }

    /// 삭제 = 기록을 다른 세부내역으로 옮기거나 함께 지움. 모든 기기에서 사라져요.
    static func delete(_ d: ActivityDetail, moveTo target: ActivityDetail?, ctx: ModelContext) {
        if let target {
            reassign(from: d, to: target)
        } else {
            for a in d.actuals ?? [] { ctx.delete(a) }
            for p in d.plans ?? [] { ctx.delete(p) }
            for g in d.goals ?? [] { ctx.delete(g) }
        }
        for l in d.calendarLinks ?? [] { l.detail = nil; l.mode = .ignore }
        for r in d.reminderLinks ?? [] { ctx.delete(r) }
        ctx.delete(d)
        save(ctx)
    }

    static func delete(_ c: ActivityCategory, moveTo target: ActivityDetail?, ctx: ModelContext) {
        for d in c.details ?? [] {
            if let target {
                reassign(from: d, to: target)
            } else {
                for a in d.actuals ?? [] { ctx.delete(a) }
                for p in d.plans ?? [] { ctx.delete(p) }
            }
            for l in d.calendarLinks ?? [] { l.detail = nil; l.mode = .ignore }
        }
        ctx.delete(c)
        save(ctx)
    }

    /// iCloud까지 지워요 (카테고리 · 시간표는 남겨요).
    static func deleteAllRecords(_ ctx: ModelContext) {
        for r in (try? ctx.fetch(FetchDescriptor<ActualRecord>())) ?? [] { ctx.delete(r) }
        for p in (try? ctx.fetch(FetchDescriptor<PlanBlock>())) ?? [] { ctx.delete(p) }
        for s in (try? ctx.fetch(FetchDescriptor<DaySummary>())) ?? [] { ctx.delete(s) }
        save(ctx)
    }

    // MARK: 하루 마감

    /// 그날 일정과 시간표를 PlanBlock으로 스냅샷하고 DaySummary를 저장해요.
    static func closeDay(day: Date, clock: DayClock, items: [PlanItem], matchRate: Double?, note: String, ctx: ModelContext) {
        for item in items where item.block == nil && (item.kind == .calendar || item.kind == .timetable) {
            _ = materialize(item, ctx: ctx)
        }
        let key = DayClock.dayKey(day)
        let s = summary(dayKey: key, ctx: ctx) ?? {
            let n = DaySummary(dayKey: key, rangeStartMinute: clock.startMinute, rangeEndMinute: clock.endMinute)
            ctx.insert(n)
            return n
        }()
        s.note = note
        s.matchRate = matchRate
        s.closedAt = Date()
        s.rangeStartMinute = clock.startMinute
        s.rangeEndMinute = clock.endMinute
        s.updatedAt = Date()
        save(ctx)
    }

    /// 지난 날은 그날 저장한 범위를 써요.
    static func clock(for day: Date, current: DayClock, ctx: ModelContext) -> DayClock {
        if let s = summary(dayKey: DayClock.dayKey(day), ctx: ctx) {
            return DayClock(startMinute: s.rangeStartMinute, endMinute: s.rangeEndMinute)
        }
        return current
    }
}
