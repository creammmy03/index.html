import SwiftData
import SwiftUI

struct ReplanRequest: Identifiable {
    let id = UUID()
    let day: Date
    let clock: DayClock
    let detail: ActivityDetail
    let minutes: Int
}

enum ReplanStrategy: String, CaseIterable, Identifiable {
    case pushLater = "뒤로 밀기"
    case tomorrow = "내일로"
    case shrink = "줄여서 넣기"
    var id: String { rawValue }
}

struct ReplanPlacement: Identifiable {
    let id: String
    let title: String
    let hex: String
    let start: Date
    let end: Date
    let originalStart: Date
    let isNew: Bool
    let isFixed: Bool
    let item: PlanItem?
    var movedMinutes: Int { Int(start.timeIntervalSince(originalStart) / 60) }
}

/// 남은 하루를 다시 맞추는 계산. 캘린더 일정은 고정이에요.
enum Replanner {
    static func placements(items: [PlanItem], now: Date, detail: ActivityDetail, minutes: Int,
                           strategy: ReplanStrategy, range: DateInterval,
                           tomorrowItems: [PlanItem], tomorrowRange: DateInterval) -> (today: [ReplanPlacement], tomorrow: ReplanPlacement?) {
        let future = items.filter { $0.end > now }
        let fixed = future.filter { $0.isFixed || $0.start < now }
        let movable = future.filter { !($0.isFixed || $0.start < now) }.sorted { $0.start < $1.start }
        let duration = Double(minutes) * 60
        let newTitle = "\(detail.fullName) · 밀린 \(Fmt.duration(minutes))"
        var out: [ReplanPlacement] = fixed.map {
            ReplanPlacement(id: $0.key, title: $0.title, hex: $0.colorHex, start: $0.start, end: $0.end,
                            originalStart: $0.start, isNew: false, isFixed: true, item: $0)
        }

        func place(_ start: Date, _ dur: TimeInterval, avoiding blockers: [(Date, Date)]) -> Date {
            var s = start
            var moved = true
            while moved {
                moved = false
                for (bs, be) in blockers where bs < s.addingTimeInterval(dur) && be > s {
                    s = be
                    moved = true
                }
            }
            return s
        }
        let fixedSpans = fixed.map { ($0.start, $0.end) }
        let cursorStart = now.roundedUp(toMinutes: 5)

        switch strategy {
        case .pushLater:
            var cursor = cursorStart
            let s = place(cursor, duration, avoiding: fixedSpans)
            out.append(ReplanPlacement(id: "new", title: newTitle, hex: detail.colorHex, start: s, end: s.addingTimeInterval(duration),
                                       originalStart: s, isNew: true, isFixed: false, item: nil))
            cursor = s.addingTimeInterval(duration)
            for item in movable {
                let d = item.end.timeIntervalSince(item.start)
                let ns = place(max(item.start, cursor), d, avoiding: fixedSpans)
                out.append(ReplanPlacement(id: item.key, title: item.title, hex: item.colorHex, start: ns, end: ns.addingTimeInterval(d),
                                           originalStart: item.start, isNew: false, isFixed: false, item: item))
                cursor = ns.addingTimeInterval(d)
            }
            return (out, nil)

        case .shrink:
            out += movable.map {
                ReplanPlacement(id: $0.key, title: $0.title, hex: $0.colorHex, start: $0.start, end: $0.end,
                                originalStart: $0.start, isNew: false, isFixed: false, item: $0)
            }
            let busy = (fixedSpans + movable.map { ($0.start, $0.end) }).sorted { $0.0 < $1.0 }
            var cursor = cursorStart
            for (bs, be) in busy {
                if bs.timeIntervalSince(cursor) >= 15 * 60 { break }
                cursor = max(cursor, be)
            }
            let next = busy.first { $0.0 >= cursor }?.0 ?? range.end
            let gap = max(0, min(next, range.end).timeIntervalSince(cursor))
            if gap >= 15 * 60 {
                let d = min(duration, gap)
                out.append(ReplanPlacement(id: "new", title: "\(detail.fullName) · \(Fmt.duration(Int(d / 60)))로 줄여서", hex: detail.colorHex,
                                           start: cursor, end: cursor.addingTimeInterval(d), originalStart: cursor,
                                           isNew: true, isFixed: false, item: nil))
            }
            return (out, nil)

        case .tomorrow:
            out += movable.map {
                ReplanPlacement(id: $0.key, title: $0.title, hex: $0.colorHex, start: $0.start, end: $0.end,
                                originalStart: $0.start, isNew: false, isFixed: false, item: $0)
            }
            let busy = tomorrowItems.map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
            var cursor = tomorrowRange.start.addingTimeInterval(2 * 3600)
            cursor = place(cursor, duration, avoiding: busy)
            let t = ReplanPlacement(id: "new", title: newTitle, hex: detail.colorHex, start: cursor, end: cursor.addingTimeInterval(duration),
                                    originalStart: cursor, isNew: true, isFixed: false, item: nil)
            return (out, t)
        }
    }
}

/// 15 · 남은 하루 다시 맞추기 (large)
struct ReplanSheet: View {
    let request: ReplanRequest
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strategy: ReplanStrategy = .pushLater
    @State private var now = Date()

    private var provider: DayDataProvider { DayDataProvider(ctx: ctx, calendar: calendarService) }

    var body: some View {
        let todayItems = provider.items(for: request.day, now: now)
        let tomorrow = DayClock.addDays(1, to: request.day)
        let tomorrowItems = provider.items(for: tomorrow, now: now)
        let range = request.clock.range(for: request.day)
        let result = Replanner.placements(items: todayItems, now: now, detail: request.detail, minutes: request.minutes,
                                          strategy: strategy, range: range, tomorrowItems: tomorrowItems,
                                          tomorrowRange: request.clock.range(for: tomorrow))
        let windowStart = DayClock.calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let lastEnd = (result.today.map(\.end) + todayItems.filter { $0.end > now }.map(\.end)).max() ?? now
        let windowEnd = max(windowStart.addingTimeInterval(4 * 3600), min(lastEnd.addingTimeInterval(1800), windowStart.addingTimeInterval(9 * 3600)))
        let metrics = TimelineMetrics(range: DateInterval(start: windowStart, end: windowEnd), hourHeight: 52, topInset: 6)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(request.detail.category?.name ?? request.detail.name) \(Fmt.duration(request.minutes))이 밀렸어요")
                            .font(.title3.bold())
                        Text("\(Fmt.hm(now)) 이후 일정을 이렇게 바꿀까요? 캘린더 일정은 그대로 둬요.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Picker("방법", selection: $strategy) {
                        ForEach(ReplanStrategy.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let t = result.tomorrow {
                        Label("내일 \(Fmt.range(t.start, t.end))에 \(request.detail.name) \(Fmt.duration(request.minutes))을 넣어요", systemImage: "arrow.turn.down.right")
                            .font(.footnote.weight(.medium))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.ground, in: .rect(cornerRadius: 12))
                    }

                    HStack(spacing: 0) {
                        Color.clear.frame(width: 40, height: 0)
                        Text("지금").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 8, height: 0)
                        Text("바뀐 후").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)

                    GeometryReader { geo in
                        let colW = (geo.size.width - 48) / 2
                        ZStack(alignment: .topLeading) {
                            HourGrid(metrics: metrics, labelWidth: 32, trailing: 0)
                            ForEach(todayItems.filter { $0.end > windowStart }) { item in
                                block(item.title, item.colorHex, metrics.y(item.start), metrics.height(item.start, item.end), fixed: item.isFixed)
                                    .frame(width: colW)
                                    .offset(x: 40)
                            }
                            ForEach(Array(result.today.enumerated()), id: \.element.id) { index, p in
                                let sub: String? = p.isFixed ? "캘린더라 고정" : (p.isNew ? Fmt.range(p.start, p.end) : (p.movedMinutes != 0 ? "+\(Fmt.duration(p.movedMinutes))" : nil))
                                block(p.title, p.hex, metrics.y(p.start), metrics.height(p.start, p.end), fixed: p.isFixed, highlight: p.isNew, subtitle: sub)
                                    .frame(width: colW)
                                    .offset(x: 48 + colW)
                                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.36).delay(Double(index) * 0.04), value: strategy)
                            }
                            Rectangle().fill(Palette.ink).frame(height: 1.5).offset(y: metrics.y(now))
                        }
                    }
                    .frame(height: metrics.totalHeight)
                    .clipped()
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("이대로 적용") { apply(result) }
                        .buttonStyle(.primary)
                    Button("직접 옮길게요") {
                        dismiss()
                        router.openPlan(on: request.day)
                    }
                    .buttonStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(Palette.surface)
            }
            .navigationTitle("다시 맞추기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
        .appSheet([.large])
    }

    private func block(_ title: String, _ hex: String, _ y: CGFloat, _ h: CGFloat, fixed: Bool, highlight: Bool = false, subtitle: String? = nil) -> some View {
        TrackBlockView(style: .plan, title: title, subtitle: subtitle, hex: hex, height: max(4, h - 2),
                       symbols: fixed ? ["lock"] : [], pending: highlight)
            .frame(height: max(4, h - 2))
            .offset(y: y + 1)
    }

    private func apply(_ result: (today: [ReplanPlacement], tomorrow: ReplanPlacement?)) {
        var undoActions: [() -> Void] = []
        let dayKey = DayClock.dayKey(request.day)
        for p in result.today where !p.isFixed {
            if p.isNew {
                let b = DataStore.makePlan(detail: request.detail, start: p.start, end: p.end, source: .manual, dayKey: dayKey, ctx: ctx)
                b.note = "다시 맞추기"
                undoActions.append { ctx.delete(b) }
            } else if let item = p.item, p.start != item.start {
                let b = DataStore.materialize(item, ctx: ctx)
                let old = (b.start, b.end)
                b.start = p.start
                b.end = p.end
                b.updatedAt = Date()
                undoActions.append { b.start = old.0; b.end = old.1 }
            }
        }
        if let t = result.tomorrow {
            let b = DataStore.makePlan(detail: request.detail, start: t.start, end: t.end, source: .manual,
                                       dayKey: DayClock.dayKey(DayClock.addDays(1, to: request.day)), ctx: ctx)
            b.note = "다시 맞추기"
            undoActions.append { ctx.delete(b) }
        }
        DataStore.save(ctx)
        toasts.show("남은 하루를 다시 맞췄어요", symbol: "arrow.triangle.2.circlepath") {
            for u in undoActions { u() }
            DataStore.save(ctx)
        }
        dismiss()
    }
}
