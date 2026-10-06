import Foundation
import WidgetKit

/// 오늘 요약을 계산해 위젯이 읽을 수 있게 저장해요.
@MainActor
enum WidgetBridge {
    static func publish(provider: DayDataProvider, now: Date = Date()) {
        let day = provider.clock.logicalDay(for: now)
        let r = provider.result(for: day, now: now)
        let total = max(1, r.range.duration)
        func frac(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(r.range.start) / total)) }
        let plan = r.items.map { WidgetSnapshot.Band(start: frac($0.start), end: frac($0.end), colorHex: $0.colorHex) }
        let actual = r.spans.map { WidgetSnapshot.Band(start: frac($0.start), end: frac($0.end), colorHex: $0.colorHex) }
        let next = r.items.first { $0.start > now }
        let snapshot = WidgetSnapshot(
            dayTitle: Fmt.dayTitle(day),
            matchRate: r.analysis.matchRate,
            planBands: plan,
            actualBands: actual,
            nowFraction: frac(now),
            nextTitle: next.map { $0.detail?.category?.name ?? $0.title },
            nextStart: next?.start,
            updatedAt: now
        )
        if snapshot != WidgetSnapshot.load().map({ var s = $0; s.updatedAt = now; return s }) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
