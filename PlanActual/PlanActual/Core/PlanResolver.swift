import Foundation

/// 계획 트랙에 그리는 블록 하나 — 직접 넣은 계획, 시간표 칸, 캘린더 일정을 하나로 모아요.
struct PlanItem: Identifiable {
    enum Kind: String {
        case manual, timetable, calendar, todo
    }

    let key: String
    var id: String { key }
    let kind: Kind
    var start: Date
    var end: Date
    let dayKey: String
    var detail: ActivityDetail?
    var title: String
    var subtitle: String?
    var colorHex: String
    var block: PlanBlock?
    var slot: TimetableSlot?
    var event: CalendarEventInfo?
    var lane = 0
    var laneCount = 1
    var hasOverlap = false

    var confirmation: Confirmation? { block?.confirmation }
    var askWhenDone: Bool { block?.askWhenDone ?? true }
    var categoryID: UUID? { detail?.category?.id }
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    var isFixed: Bool { kind == .calendar }

    /// 확인 질문을 띄워야 하는가
    func needsConfirmation(now: Date, globalAsk: Bool) -> Bool {
        globalAsk && askWhenDone && confirmation == nil && end <= now
    }
}

enum PlanResolver {
    /// 우선순위: 캘린더 일정 > 직접 넣은 계획 > 시간표.
    static func items(day: Date,
                      clock: DayClock,
                      blocks: [PlanBlock],
                      timetables: [Timetable],
                      events: [CalendarEventInfo],
                      links: [CalendarLink],
                      now: Date = Date()) -> [PlanItem] {
        let range = clock.range(for: day)
        let dayKey = DayClock.dayKey(day)
        let inRange = blocks.filter { !$0.isCancelled && $0.end > range.start && $0.start < range.end }
        var cancelledKeys = Set<String>()
        for b in blocks where b.isCancelled {
            if let k = b.slotKey { cancelledKeys.insert("tt:" + k) }
            if let e = b.ekExternalID { cancelledKeys.insert("ek:" + e + "|" + b.dayKey) }
        }

        var result: [PlanItem] = []

        // 1. 캘린더 일정
        let calendarBlocks = inRange.filter { $0.source == .calendar }
        var usedCalendarBlocks = Set<UUID>()
        for ev in events where ev.end > range.start && ev.start < range.end {
            let link = links.first { $0.calendarKey == ev.calendarKey }
            if link?.mode == .ignore { continue }
            if cancelledKeys.contains("ek:" + ev.externalID + "|" + dayKey) { continue }
            let block = calendarBlocks.first { $0.ekExternalID == ev.externalID && $0.dayKey == dayKey }
            if let block { usedCalendarBlocks.insert(block.id) }
            let detail = block?.detail ?? link?.detail
            let title = detail.map { "\($0.category?.name ?? "") · \(ev.title)" } ?? ev.title
            result.append(PlanItem(
                key: "ek:\(ev.externalID)|\(dayKey)|\(Int(ev.start.timeIntervalSince1970))",
                kind: .calendar, start: ev.start, end: ev.end, dayKey: dayKey,
                detail: detail, title: title, subtitle: ev.calendarTitle,
                colorHex: detail?.colorHex ?? ev.calendarColorHex,
                block: block, slot: nil, event: ev))
        }
        // 지난 날 스냅샷만 남은 캘린더 블록
        for b in calendarBlocks where !usedCalendarBlocks.contains(b.id) && b.end <= now {
            result.append(item(from: b, kind: .calendar, dayKey: dayKey))
        }

        // 2. 직접 넣은 계획 · 배치한 할 일
        for b in inRange where b.source == .manual || b.source == .todo {
            result.append(item(from: b, kind: b.source == .todo ? .todo : .manual, dayKey: dayKey))
        }

        // 3. 시간표 — 위 레이어와 겹치는 칸은 그날만 숨겨요.
        let upper = result
        let timetableBlocks = inRange.filter { $0.source == .timetable }
        var usedSlotKeys = Set<String>()
        if let tt = activeTimetable(for: day, in: timetables) {
            let weekday = DayClock.weekday(day)
            let slots = (tt.slots ?? []).filter { $0.weekday == weekday }
            for slot in slots {
                let slotKey = "\(dayKey)|\(slot.id.uuidString)"
                usedSlotKeys.insert(slotKey)
                if cancelledKeys.contains("tt:" + slotKey) { continue }
                let block = timetableBlocks.first { $0.slotKey == slotKey }
                let start = block?.start ?? clock.date(on: day, minute: slot.startMinute)
                let end = block?.end ?? clock.date(on: day, minute: slot.startMinute + slot.durationMinutes)
                if upper.contains(where: { $0.start < end && $0.end > start }) { continue }
                let detail = block?.detail ?? slot.detail
                let days = (tt.slots ?? [])
                    .filter { $0.detail?.id == slot.detail?.id && $0.startMinute == slot.startMinute && $0.endMinute == slot.endMinute }
                    .map(\.weekday)
                var subtitle = "\(Fmt.range(start, end)) · \(days.count > 1 ? "매주 " + Fmt.weekdays(days) : "시간표")"
                if let place = slot.place, !place.isEmpty { subtitle += " · \(place)" }
                result.append(PlanItem(
                    key: "tt:\(slotKey)", kind: .timetable, start: start, end: end, dayKey: dayKey,
                    detail: detail, title: detail?.fullName ?? "시간표", subtitle: subtitle,
                    colorHex: detail?.colorHex ?? "#52606F", block: block, slot: slot, event: nil))
            }
        }
        // 시간표가 바뀌었어도 저장된 칸은 그날의 기록으로 남겨요.
        for b in timetableBlocks where !usedSlotKeys.contains(b.slotKey ?? "") {
            if upper.contains(where: { $0.start < b.end && $0.end > b.start }) { continue }
            result.append(item(from: b, kind: .timetable, dayKey: dayKey))
        }

        result.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        return assignLanes(result)
    }

    static func item(from b: PlanBlock, kind: PlanItem.Kind, dayKey: String) -> PlanItem {
        let key: String
        switch kind {
        case .timetable: key = "tt:\(b.slotKey ?? b.id.uuidString)"
        default: key = "pb:\(b.id.uuidString)"
        }
        let title: String
        if kind == .calendar, let t = b.title {
            title = b.detail.map { "\($0.category?.name ?? "") · \(t)" } ?? t
        } else {
            title = b.detail?.fullName ?? (b.title ?? "계획")
        }
        var subtitle: String? = Fmt.range(b.start, b.end)
        if kind == .todo { subtitle = (subtitle ?? "") + " · 할 일" }
        return PlanItem(key: key, kind: kind, start: b.start, end: b.end, dayKey: b.dayKey.isEmpty ? dayKey : b.dayKey,
                        detail: b.detail, title: title, subtitle: subtitle,
                        colorHex: b.detail?.colorHex ?? "#52606F", block: b, slot: nil, event: nil)
    }

    /// 겹치는 블록은 나란히 놓고, 캘린더와 직접 계획이 겹치면 겹침 표시.
    static func assignLanes(_ items: [PlanItem]) -> [PlanItem] {
        var out = items
        var i = 0
        while i < out.count {
            var clusterEnd = out[i].end
            var j = i + 1
            while j < out.count && out[j].start < clusterEnd {
                clusterEnd = max(clusterEnd, out[j].end)
                j += 1
            }
            var laneEnds: [Date] = []
            for k in i..<j {
                if let lane = laneEnds.firstIndex(where: { $0 <= out[k].start }) {
                    out[k].lane = lane
                    laneEnds[lane] = out[k].end
                } else {
                    out[k].lane = laneEnds.count
                    laneEnds.append(out[k].end)
                }
            }
            for k in i..<j {
                out[k].laneCount = laneEnds.count
                out[k].hasOverlap = laneEnds.count > 1
            }
            i = j
        }
        return out
    }

    /// 그날 쓰는 시간표: 켜져 있고 기간 안에 드는 것 중 기간이 가장 좁은 것.
    static func activeTimetable(for day: Date, in timetables: [Timetable]) -> Timetable? {
        let d = DayClock.calendar.startOfDay(for: day)
        let candidates = timetables.filter { tt in
            guard tt.isActive else { return false }
            if let s = tt.startDate, DayClock.calendar.startOfDay(for: s) > d { return false }
            if let e = tt.endDate, DayClock.calendar.startOfDay(for: e) < d { return false }
            return true
        }
        return candidates.min { span($0) < span($1) }
    }

    private static func span(_ tt: Timetable) -> Double {
        switch (tt.startDate, tt.endDate) {
        case let (s?, e?): return e.timeIntervalSince(s)
        case (_?, nil), (nil, _?): return 1e12
        default: return 1e13
        }
    }

    enum TimetableStatus {
        case applied, scheduled, off, inactive
        var label: String {
            switch self {
            case .applied: return "적용 중"
            case .scheduled: return "예약"
            case .off: return "대기"
            case .inactive: return "꺼짐"
            }
        }
    }

    static func status(of tt: Timetable, today: Date, all: [Timetable]) -> TimetableStatus {
        if activeTimetable(for: today, in: all)?.id == tt.id { return .applied }
        guard tt.isActive else { return .inactive }
        if let s = tt.startDate, s > today { return .scheduled }
        return .off
    }

    static func periodText(_ tt: Timetable) -> String {
        switch (tt.startDate, tt.endDate) {
        case let (s?, e?): return "\(Fmt.monthDay(s)) – \(Fmt.monthDay(e))"
        case let (s?, nil): return "\(Fmt.monthDay(s))부터"
        case let (nil, e?): return "\(Fmt.monthDay(e))까지"
        default: return "기간 미정"
        }
    }
}
