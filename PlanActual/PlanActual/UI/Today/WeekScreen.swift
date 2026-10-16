import SwiftData
import SwiftUI

/// 06 · 주간 시간표 보기 — 01과 같은 화면에서 일/주 전환
struct WeekScreen: View {
    let anchor: Date
    let clock: DayClock
    @Binding var selectedDay: Date
    @Binding var mode: TodayMode

    @Environment(CalendarService.self) private var calendarService
    @Query private var blocks: [PlanBlock]
    @Query private var summaries: [DaySummary]
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    private let days: [Date]

    init(anchor: Date, clock: DayClock, selectedDay: Binding<Date>, mode: Binding<TodayMode>) {
        self.anchor = anchor
        self.clock = clock
        self._selectedDay = selectedDay
        self._mode = mode
        let days = DayClock.weekDays(containing: anchor)
        self.days = days
        let s = clock.range(for: days[0]).start
        let e = clock.range(for: days[6]).end
        _blocks = Query(filter: #Predicate<PlanBlock> { $0.start < e && $0.end > s }, sort: \PlanBlock.start)
        let keys = days.map(DayClock.dayKey)
        _summaries = Query(filter: #Predicate<DaySummary> { keys.contains($0.dayKey) })
    }

    private var today: Date { clock.logicalDay(for: Date()) }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let now = tl.date
            let showCal = prefsList.first?.showCalendarEvents ?? false
            let weekRange = DateInterval(start: clock.range(for: days[0]).start, end: clock.range(for: days[6]).end)
            let events = showCal ? calendarService.events(in: weekRange) : []
            let columns = days.map { d in
                PlanResolver.items(day: d, clock: clock, blocks: blocks, timetables: timetables, events: events, links: links, now: now)
            }
            // 모든 요일을 같은 시각 축으로 — 하루 범위의 분 기준
            let metrics = TimelineMetrics(range: DateInterval(start: clock.range(for: days[0]).start, duration: Double(clock.lengthMinutes) * 60), hourHeight: 36)
            VStack(spacing: 0) {
                header
                dayHeader
                ScrollView {
                    WeekGrid(days: days, columns: columns, clock: clock, metrics: metrics, today: today, now: now)
                        .frame(height: metrics.totalHeight)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            if v.translation.width < -60 { selectedDay = DayClock.addDays(7, to: anchor) }
                            else if v.translation.width > 60 { selectedDay = DayClock.addDays(-7, to: anchor) }
                        }
                )
            }
        }
        .toastHost()
    }

    private var header: some View {
        let active = PlanResolver.activeTimetable(for: anchor, in: timetables)
        return VStack(spacing: 12) {
            HStack {
                Text("\(Fmt.monthDay(days[0])) – \(Fmt.dayNumber(days[6]))일")
                    .font(.title2.bold())
                    .monospacedDigit()
                Spacer()
                Picker("보기", selection: $mode) {
                    Text("일").tag(TodayMode.day)
                    Text("주").tag(TodayMode.week)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
            }
            HStack {
                NavigationLink(value: TodayRoute.timetables) {
                    HStack(spacing: 6) {
                        Image(systemName: "tablecells").font(.caption)
                        Text("시간표 · \(active?.name ?? "없음")").font(.footnote.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.inkSecondary)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Palette.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Palette.line))
                }
                .buttonStyle(.pressable)
                Spacer()
                Label("캘린더 일정", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var dayHeader: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 26, height: 0)
            ForEach(days, id: \.self) { d in
                let isToday = DayClock.isSameDay(d, today)
                let rate = summaries.first { $0.dayKey == DayClock.dayKey(d) }?.matchRate
                Button {
                    selectedDay = d
                    mode = .day
                } label: {
                    VStack(spacing: 2) {
                        Text(Fmt.weekdayShort(d)).font(.caption2.weight(.medium)).opacity(0.8)
                        Text(Fmt.dayNumber(d)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Capsule()
                            .fill(rate == nil ? Color.clear : (isToday ? Palette.ground.opacity(0.3) : Palette.line))
                            .frame(width: 16, height: 3)
                            .overlay(alignment: .leading) {
                                if let rate { Capsule().fill(isToday ? Palette.ground : Palette.ink).frame(width: 16 * rate, height: 3) }
                            }
                    }
                    .foregroundStyle(isToday ? Palette.ground : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(isToday ? Palette.ink : Color.clear, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(Fmt.monthDay(d)) \(Fmt.weekdayLong(d))\(rate.map { ", 일치 \(Fmt.percent($0))" } ?? "")")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// 주간 격자 — 요일 7열 · 열 간격 2pt · 오늘 열 배경
struct WeekGrid: View {
    let days: [Date]
    let columns: [[PlanItem]]
    let clock: DayClock
    let metrics: TimelineMetrics
    let today: Date
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ForEach(Array(metrics.hourMarks.enumerated()), id: \.offset) { _, mark in
                    Text(mark.label)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkTertiary)
                        .offset(y: mark.y - 6)
                }
            }
            .frame(width: 26, alignment: .topTrailing)
            .padding(.trailing, 2)

            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = DayClock.isSameDay(day, today)
                let range = clock.range(for: day)
                // 이 열의 날짜를 첫 날 기준 좌표로 옮겨요.
                let shift = range.start.timeIntervalSince(metrics.range.start)
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8).fill(isToday ? Palette.fill.opacity(0.7) : Color.clear)
                        ForEach(Array(metrics.hourMarks.enumerated()), id: \.offset) { _, mark in
                            Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1).offset(y: mark.y)
                        }
                        ForEach(columns[index]) { item in
                            let s = item.start.addingTimeInterval(-shift)
                            let e = item.end.addingTimeInterval(-shift)
                            let laneW = geo.size.width / CGFloat(max(1, item.laneCount))
                            TrackBlockView(style: .plan, title: item.detail?.name ?? item.title, hex: item.colorHex,
                                           height: max(4, metrics.height(s, e) - 2),
                                           symbols: item.kind == .calendar ? ["calendar"] : [],
                                           dimmed: item.end <= now, compact: true)
                                .frame(width: max(0, laneW - 1), height: max(4, metrics.height(s, e) - 2))
                                .offset(x: laneW * CGFloat(item.lane), y: metrics.y(s) + 1)
                                .accessibilityLabel("\(Fmt.weekdayLong(day)) \(item.title), \(Fmt.range(item.start, item.end))")
                        }
                        if isToday && range.contains(now) {
                            let y = metrics.y(now.addingTimeInterval(-shift))
                            Rectangle().fill(Palette.ink).frame(height: 2).offset(y: y - 1)
                            Circle().fill(Palette.ink).frame(width: 8, height: 8).offset(x: -4, y: y - 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
