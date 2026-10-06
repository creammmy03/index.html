import Foundation

/// 실제 트랙에 그리는 기록 하나.
struct ActualSpan: Identifiable {
    let id: UUID
    let record: ActualRecord
    let start: Date
    let end: Date
    let isRunning: Bool
    var detail: ActivityDetail? { record.detail }
    var categoryID: UUID? { record.detail?.category?.id }
    var colorHex: String { record.detail?.colorHex ?? "#52606F" }
    var title: String { record.detail?.fullName ?? "미분류" }
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    static func make(_ records: [ActualRecord], in range: DateInterval, now: Date) -> [ActualSpan] {
        records.compactMap { r in
            let end = r.end ?? max(now, r.start)
            guard end > range.start, r.start < range.end, end > r.start else { return nil }
            return ActualSpan(id: r.id, record: r, start: r.start, end: end, isRunning: r.end == nil)
        }
        .sorted { $0.start < $1.start }
    }
}

struct SeamSegment: Identifiable, Hashable {
    var id: Int { startMinute }
    let startMinute: Int
    let endMinute: Int
    let matched: Bool
}

struct CategoryTotal: Identifiable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let name: String
    let colorHex: String
    var planMinutes: Int
    var actualMinutes: Int
    var diff: Int { actualMinutes - planMinutes }
}

/// 하루 범위를 분 단위로 펼쳐 계획과 실제의 카테고리를 비교해요.
struct DayAnalysis {
    static let uncategorized = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    let range: DateInterval
    let totalMinutes: Int
    let elapsedMinutes: Int
    let plan: [UUID?]
    let actual: [UUID?]
    /// 확인에서 '했어요'·'건너뜀'으로 답한 계획 분 — 밀린 시간에서 빼요.
    let planSettled: [Bool]
    let planDetail: [ActivityDetail?]

    /// 하루 범위 안의 지난 시간 중 계획이나 기록이 있는 분 가운데 카테고리가 같은 분의 비율.
    var matchRate: Double? {
        var union = 0, match = 0
        for i in 0..<elapsedMinutes {
            let p = plan[i], a = actual[i]
            if p != nil || a != nil {
                union += 1
                if let p, let a, p == a { match += 1 }
            }
        }
        return union > 0 ? Double(match) / Double(union) : nil
    }

    var seam: [SeamSegment] {
        var out: [SeamSegment] = []
        var runStart = 0
        var state: Bool? = nil
        func close(_ i: Int) {
            if let s = state { out.append(SeamSegment(startMinute: runStart, endMinute: i, matched: s)) }
        }
        for i in 0..<elapsedMinutes {
            let p = plan[i], a = actual[i]
            let s: Bool? = (p == nil && a == nil) ? nil : (p != nil && p == a)
            if s != state {
                close(i)
                runStart = i
                state = s
            }
        }
        close(elapsedMinutes)
        return out
    }

    /// 계획한 카테고리를 못 한 분 (지난 시간만)
    var missedByCategory: [UUID: Int] {
        var m: [UUID: Int] = [:]
        for i in 0..<elapsedMinutes {
            guard let p = plan[i], !planSettled[i], p != DayAnalysis.uncategorized else { continue }
            if actual[i] != p { m[p, default: 0] += 1 }
        }
        return m
    }

    /// 가장 많이 밀린 세부내역과 분
    func topMissed() -> (detail: ActivityDetail, minutes: Int)? {
        guard let top = missedByCategory.max(by: { $0.value < $1.value }), top.value >= 15 else { return nil }
        let cat = top.key, minutes = top.value
        var counts: [UUID: (ActivityDetail, Int)] = [:]
        for i in 0..<elapsedMinutes where plan[i] == cat && actual[i] != cat {
            if let d = planDetail[i] {
                counts[d.id] = (d, (counts[d.id]?.1 ?? 0) + 1)
            }
        }
        guard let best = counts.values.max(by: { $0.1 < $1.1 }) else { return nil }
        return (best.0, minutes)
    }

    func totals(categories: [ActivityCategory]) -> [CategoryTotal] {
        var plans: [UUID: Int] = [:], actuals: [UUID: Int] = [:]
        for i in 0..<totalMinutes { if let p = plan[i] { plans[p, default: 0] += 1 } }
        for i in 0..<elapsedMinutes { if let a = actual[i] { actuals[a, default: 0] += 1 } }
        let ids = Set(plans.keys).union(actuals.keys)
        return ids.map { id in
            let c = categories.first { $0.id == id }
            return CategoryTotal(categoryID: id, name: c?.name ?? "미분류", colorHex: c?.colorHex ?? "#8A8A85",
                                 planMinutes: plans[id] ?? 0, actualMinutes: actuals[id] ?? 0)
        }
        .sorted { max($0.planMinutes, $0.actualMinutes) > max($1.planMinutes, $1.actualMinutes) }
    }

    /// 기록이 빈 지난 시간 (15분 이상)
    func gaps(minMinutes: Int = 15) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var start: Int? = nil
        for i in 0...elapsedMinutes {
            let empty = i < elapsedMinutes && actual[i] == nil
            if empty {
                if start == nil { start = i }
            } else if let s = start {
                if i - s >= minMinutes { out.append(s...(i - 1)) }
                start = nil
            }
        }
        return out
    }

    func date(atMinute m: Int) -> Date { range.start.addingTimeInterval(Double(m) * 60) }
}

enum MatchEngine {
    static func analyze(range: DateInterval, items: [PlanItem], actuals: [ActualSpan], now: Date) -> DayAnalysis {
        let total = max(0, min(1440, Int(range.duration / 60)))
        let elapsed = max(0, min(total, Int(now.timeIntervalSince(range.start) / 60)))
        var plan = [UUID?](repeating: nil, count: total)
        var settled = [Bool](repeating: false, count: total)
        var planDetail = [ActivityDetail?](repeating: nil, count: total)
        var actual = [UUID?](repeating: nil, count: total)

        func bounds(_ s: Date, _ e: Date) -> Range<Int>? {
            let a = max(0, Int(floor(s.timeIntervalSince(range.start) / 60)))
            let b = min(total, Int(ceil(e.timeIntervalSince(range.start) / 60)))
            return a < b ? a..<b : nil
        }

        // 시간표 → 직접 계획 → 캘린더 순서로 덮어써 우선순위를 맞춰요.
        let order: [PlanItem.Kind: Int] = [.timetable: 0, .manual: 1, .todo: 1, .calendar: 2]
        for item in items.sorted(by: { (order[$0.kind] ?? 0) < (order[$1.kind] ?? 0) }) {
            guard let r = bounds(item.start, item.end) else { continue }
            let cat = item.categoryID ?? DayAnalysis.uncategorized
            let isSettled = item.confirmation == .done || item.confirmation == .skip
            for i in r {
                plan[i] = cat
                settled[i] = isSettled
                planDetail[i] = item.detail
            }
        }
        for span in actuals {
            guard let r = bounds(span.start, span.end) else { continue }
            let cat = span.categoryID ?? DayAnalysis.uncategorized
            for i in r { actual[i] = cat }
        }
        return DayAnalysis(range: range, totalMinutes: total, elapsedMinutes: elapsed,
                           plan: plan, actual: actual, planSettled: settled, planDetail: planDetail)
    }
}
