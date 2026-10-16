import SwiftData
import SwiftUI

enum TodayMode: Hashable {
    case day, week
}

enum TodayRoute: Hashable {
    case timetables
    case gapFill(Date)
}

/// 탭 1 · 오늘 — 계획과 실제 두 트랙 (01) / 주간 시간표 (06)
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @State private var selectedDay = DayClock.standard.logicalDay(for: Date())
    @State private var mode: TodayMode = .day
    @State private var didInit = false
    @State private var closeTarget: Date?

    var body: some View {
        let clock = DayClock(prefsList.first)
        NavigationStack {
            Group {
                switch mode {
                case .day:
                    DayScreen(day: selectedDay, clock: clock, selectedDay: $selectedDay, mode: $mode) { day in
                        closeTarget = day
                        router.showDayClose = true
                    }
                case .week:
                    WeekScreen(anchor: selectedDay, clock: clock, selectedDay: $selectedDay, mode: $mode)
                }
            }
            .background(Palette.ground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .timetables: TimetablesView()
                case .gapFill(let day): GapFillView(day: day, closesDay: false)
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            selectedDay = clock.logicalDay(for: Date())
            didInit = true
        }
        .fullScreenCover(isPresented: Bindable(router).showDayClose, onDismiss: { closeTarget = nil }) {
            DayCloseFlow(day: closeTarget ?? clock.logicalDay(for: Date()))
        }
    }
}

// MARK: - 일 보기

struct DayScreen: View {
    let day: Date
    let clock: DayClock
    @Binding var selectedDay: Date
    @Binding var mode: TodayMode
    let onClose: (Date) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(CalendarService.self) private var calendarService

    @Query private var blocks: [PlanBlock]
    @Query private var records: [ActualRecord]
    @Query private var summaries: [DaySummary]
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var confirmItem: PlanItem?
    @State private var editRecord: ActualRecord?
    @State private var replan: ReplanRequest?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var feedback = 0

    init(day: Date, clock: DayClock, selectedDay: Binding<Date>, mode: Binding<TodayMode>, onClose: @escaping (Date) -> Void) {
        self.day = day
        self.clock = clock
        self._selectedDay = selectedDay
        self._mode = mode
        self.onClose = onClose
        let range = clock.range(for: day)
        let s = range.start, e = range.end, early = s.addingTimeInterval(-86400)
        _blocks = Query(filter: #Predicate<PlanBlock> { $0.start < e && $0.end > s }, sort: \PlanBlock.start)
        _records = Query(filter: #Predicate<ActualRecord> { $0.start < e && $0.start > early }, sort: \ActualRecord.start)
        let keys = DayClock.weekDays(containing: day).map(DayClock.dayKey)
        _summaries = Query(filter: #Predicate<DaySummary> { keys.contains($0.dayKey) })
    }

    struct Model {
        let clock: DayClock
        let range: DateInterval
        let metrics: TimelineMetrics
        let items: [PlanItem]
        let spans: [ActualSpan]
        let analysis: DayAnalysis
    }

    private var prefs: AppPreferences? { prefsList.first }
    private var today: Date { clock.logicalDay(for: Date()) }
    private var isToday: Bool { DayClock.isSameDay(day, today) }

    private func dayClock() -> DayClock {
        if let s = summaries.first(where: { $0.dayKey == DayClock.dayKey(day) }) {
            return DayClock(startMinute: s.rangeStartMinute, endMinute: s.rangeEndMinute)
        }
        return clock
    }

    func model(now: Date) -> Model {
        let c = dayClock()
        let range = c.range(for: day)
        let events = (prefs?.showCalendarEvents ?? false) ? calendarService.events(in: range) : []
        let items = PlanResolver.items(day: day, clock: c, blocks: blocks, timetables: timetables, events: events, links: links, now: now)
        let spans = ActualSpan.make(records, in: range, now: now)
        let analysis = MatchEngine.analyze(range: range, items: items, actuals: spans, now: now)
        return Model(clock: c, range: range, metrics: TimelineMetrics(range: range, hourHeight: 52), items: items, spans: spans, analysis: analysis)
    }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let now = tl.date
            let m = model(now: now)
            VStack(spacing: 0) {
                header(m, now: now)
                columnLabels
                ScrollView {
                    VStack(spacing: 20) {
                        DayTimelineCanvas(
                            metrics: m.metrics, items: m.items, spans: m.spans, seam: m.analysis.seam,
                            now: now, showsNow: isToday, globalAsk: prefs?.askWhenDone ?? true,
                            onTapPlan: { confirmItem = $0 },
                            onTapActual: { editRecord = $0.record }
                        )
                        .frame(height: m.metrics.totalHeight)
                        .overlay(alignment: .top) {
                            if m.items.isEmpty && day >= DayClock.calendar.startOfDay(for: today) {
                                // 하루 끝 무렵이면 카드가 타임라인 밖(하루 마감 버튼 위)으로 넘치지 않게 끝에서 멈춰요.
                                emptyPlanCard.padding(.top, max(8, min(m.metrics.y(now) - 40, m.metrics.totalHeight - 180)))
                            }
                        }
                        if day <= today {
                            Button {
                                onClose(day)
                            } label: {
                                Label("하루 마감하기", systemImage: "moon.stars")
                            }
                            .buttonStyle(.secondary)
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollPosition($scroll)
                .onAppear { scrollToNow(m, now: now) }
                .onChange(of: day) { _, _ in scrollToNow(model(now: Date()), now: Date()) }
            }
            .onChange(of: router.pendingConfirmKey) { _, key in
                openPending(key, items: m.items)
            }
            .onAppear { openPending(router.pendingConfirmKey, items: m.items) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TimerBar(currentPlan: currentPlan())
        }
        .toastHost()
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .sheet(item: $confirmItem) { item in
            ConfirmSheet(item: item, spans: model(now: Date()).spans) { kind, other in
                record(item, kind, other: other)
            }
        }
        .sheet(item: $editRecord) { r in
            ActualEditSheet(record: r)
        }
        .sheet(item: $replan) { req in
            ReplanSheet(request: req)
        }
    }

    private func currentPlan() -> PlanItem? {
        let now = Date()
        return model(now: now).items.first { $0.start <= now && $0.end > now }
    }

    private func scrollToNow(_ m: Model, now: Date) {
        let target = m.range.contains(now) ? m.metrics.y(now) - 180 : m.metrics.y(m.items.first?.start ?? m.range.start) - 40
        scroll.scrollTo(y: max(0, target))
    }

    private func openPending(_ key: String?, items: [PlanItem]) {
        guard let key else { return }
        if let item = items.first(where: { $0.key == key }) {
            confirmItem = item
        }
        router.pendingConfirmKey = nil
    }

    private func record(_ item: PlanItem, _ kind: Confirmation, other: ActivityDetail?) {
        let block = DataStore.materialize(item, ctx: ctx)
        let undo = DataStore.confirm(block, as: kind, otherDetail: other, ctx: ctx)
        feedback += 1
        let name = item.detail?.fullName ?? item.title
        toasts.show("\(name) · \(kind.label)", symbol: kind.symbol, undo: undo)
    }

    // MARK: 머리

    @ViewBuilder
    private func header(_ m: Model, now: Date) -> some View {
        let rate = m.analysis.matchRate
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(Fmt.dayTitle(day))
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button {
                    onClose(day)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.lefthalf.filled").font(.caption)
                        Text(Fmt.percent(rate)).font(.footnote.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    .frame(height: 32)
                    .background(Palette.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Palette.line))
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.ink)
                .accessibilityLabel("일치 \(Fmt.percent(rate)), 하루 마감 열기")
                Picker("보기", selection: $mode) {
                    Text("일").tag(TodayMode.day)
                    Text("주").tag(TodayMode.week)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
            }
            WeekStrip(
                days: DayClock.weekDays(containing: day),
                selected: day,
                today: today,
                rates: weekRates(todayRate: isToday ? rate : nil),
                onSelect: { selectedDay = $0 },
                onShiftWeek: { selectedDay = DayClock.addDays(7 * $0, to: day) }
            )
            if isToday, let missed = m.analysis.topMissed() {
                Button {
                    replan = ReplanRequest(day: day, clock: m.clock, detail: missed.detail, minutes: missed.minutes)
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Palette.diverge).frame(width: 8, height: 8)
                        Text("\(missed.detail.category?.name ?? missed.detail.name) \(Fmt.duration(missed.minutes))이 밀렸어요")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 2) {
                            Text("다시 맞추기")
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Palette.divergeInk)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Palette.divergeTint, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func weekRates(todayRate: Double?) -> [String: Double] {
        var out: [String: Double] = [:]
        for s in summaries { if let r = s.matchRate { out[s.dayKey] = r } }
        if let todayRate { out[DayClock.dayKey(today)] = todayRate }
        return out
    }

    private var columnLabels: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 52, height: 0)
            Text("계획").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
            Color.clear.frame(width: 16, height: 0)
            Text("실제").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.inkSecondary)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var emptyPlanCard: some View {
        VStack(spacing: 10) {
            Text("아직 계획이 없어요").font(.headline)
            Text("계획을 세우면 실제와 나란히 비교해요.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            Button("첫 계획 만들기") { router.openPlan(on: day) }
                .buttonStyle(.primary)
                .frame(maxWidth: 220)
        }
        .padding(20)
        .background(Palette.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
        .padding(.horizontal, 40)
    }
}

// MARK: - 주간 스트립

struct WeekStrip: View {
    let days: [Date]
    let selected: Date
    let today: Date
    let rates: [String: Double]
    let onSelect: (Date) -> Void
    let onShiftWeek: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let isSel = DayClock.isSameDay(d, selected)
                let isToday = DayClock.isSameDay(d, today)
                let rate = rates[DayClock.dayKey(d)]
                Button {
                    onSelect(d)
                } label: {
                    VStack(spacing: 3) {
                        Text(Fmt.weekdayShort(d))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isSel ? Palette.ground.opacity(0.8) : Palette.inkSecondary)
                        Text(Fmt.dayNumber(d))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .underline(isToday && !isSel)
                        Capsule()
                            .fill(rate == nil ? Color.clear : (isSel ? Palette.ground.opacity(0.3) : Palette.line))
                            .frame(width: 18, height: 3)
                            .overlay(alignment: .leading) {
                                if let rate {
                                    Capsule().fill(isSel ? Palette.ground : Palette.ink).frame(width: 18 * rate, height: 3)
                                }
                            }
                    }
                    .foregroundStyle(isSel ? Palette.ground : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isSel ? Palette.ink : Color.clear, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(Fmt.monthDay(d)) \(Fmt.weekdayLong(d))\(isToday ? ", 오늘" : "")\(rate.map { ", 일치 \(Fmt.percent($0))" } ?? "")")
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    if v.translation.width < -50 { onShiftWeek(1) }
                    else if v.translation.width > 50 { onShiftWeek(-1) }
                }
        )
    }
}

// MARK: - 두 트랙 타임라인

struct DayTimelineCanvas: View {
    let metrics: TimelineMetrics
    let items: [PlanItem]
    let spans: [ActualSpan]
    let seam: [SeamSegment]
    let now: Date
    let showsNow: Bool
    let globalAsk: Bool
    let onTapPlan: (PlanItem) -> Void
    let onTapActual: (ActualSpan) -> Void

    private let labelW: CGFloat = 52
    private let seamW: CGFloat = 16
    private let trailing: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let colW = max(0, (geo.size.width - labelW - seamW - trailing) / 2)
            let seamX = labelW + colW
            let actualX = seamX + seamW
            ZStack(alignment: .topLeading) {
                HourGrid(metrics: metrics, labelWidth: 44, trailing: trailing)

                ForEach(items) { item in
                    let laneW = colW / CGFloat(max(1, item.laneCount))
                    let h = max(4, metrics.height(item.start, item.end) - 2)
                    Button {
                        onTapPlan(item)
                    } label: {
                        TrackBlockView(style: .plan, title: item.title, subtitle: Fmt.range(item.start, item.end),
                                       hex: item.colorHex, height: h, symbols: symbols(item),
                                       pending: item.needsConfirmation(now: now, globalAsk: globalAsk))
                    }
                    .buttonStyle(.pressable)
                    .frame(width: max(0, laneW - (item.laneCount > 1 ? 2 : 0)), height: h)
                    .offset(x: labelW + laneW * CGFloat(item.lane), y: metrics.y(item.start) + 1)
                    .accessibilityLabel(accessibility(item))
                }

                SeamView(segments: seam, metrics: metrics,
                         nowY: showsNow ? metrics.y(now) : metrics.y(metrics.range.end),
                         endY: metrics.y(metrics.range.end))
                    .frame(width: seamW, height: metrics.totalHeight)
                    .offset(x: seamX)

                ForEach(spans) { span in
                    let h = max(4, metrics.height(span.start, span.end) - 2)
                    Button {
                        onTapActual(span)
                    } label: {
                        TrackBlockView(style: .actual, title: span.title,
                                       subtitle: span.isRunning ? "\(Fmt.hm(span.start))–" : Fmt.range(span.start, span.end),
                                       hex: span.colorHex, height: h, running: span.isRunning)
                    }
                    .buttonStyle(.pressable)
                    .frame(width: colW, height: h)
                    .offset(x: actualX, y: metrics.y(span.start) + 1)
                    .accessibilityLabel("\(span.title), \(Fmt.hm(span.start))부터 \(span.isRunning ? "기록 중" : Fmt.hm(span.end) + "까지"), 실제")
                }

                if showsNow && metrics.range.contains(now) {
                    NowLine(now: now)
                        .padding(.trailing, trailing)
                        .offset(y: metrics.y(now) - 9)
                }
            }
        }
    }

    private func symbols(_ item: PlanItem) -> [String] {
        var s: [String] = []
        if let c = item.confirmation { s.append(c.symbol) }
        if item.kind == .calendar { s.append("calendar") }
        if item.kind == .todo { s.append("checklist") }
        return s
    }

    private func accessibility(_ item: PlanItem) -> String {
        var parts = [item.title, "\(Fmt.hm(item.start))부터 \(Fmt.hm(item.end))까지", "계획"]
        if let c = item.confirmation { parts.append(c.label) }
        else if item.needsConfirmation(now: now, globalAsk: globalAsk) { parts.append("확인 필요") }
        if item.kind == .calendar { parts.append("캘린더 일정") }
        return parts.joined(separator: ", ")
    }
}
