import SwiftData
import SwiftUI

enum PlanRoute: Hashable {
    case timetables
    case calendar
}

struct PlanSelection: Equatable {
    var start: Date
    var end: Date
}

/// 탭 2 · 계획 짜기 (02) — 기본은 내일
struct PlanView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @State private var day = DayClock.addDays(1, to: DayClock.calendar.startOfDay(for: Date()))
    @State private var path: [PlanRoute] = []
    @State private var didInit = false

    var body: some View {
        let clock = DayClock(prefsList.first)
        NavigationStack(path: $path) {
            PlanDayScreen(day: $day, clock: clock, path: $path)
                .id(DayClock.dayKey(day))
                .background(Palette.ground)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PlanRoute.self) { route in
                    switch route {
                    case .timetables: TimetablesView()
                    case .calendar: CalendarSyncView()
                    }
                }
        }
        .onAppear {
            if let d = router.planJumpDate {
                day = d
                router.planJumpDate = nil
            } else if !didInit {
                day = DayClock.addDays(1, to: clock.logicalDay(for: Date()))
            }
            didInit = true
        }
        .onChange(of: router.planJumpDate) { _, d in
            guard let d else { return }
            day = d
            router.planJumpDate = nil
        }
    }
}

struct PlanDayScreen: View {
    @Binding var day: Date
    let clock: DayClock
    @Binding var path: [PlanRoute]

    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @Environment(ToastCenter.self) private var toasts
    @Query private var blocks: [PlanBlock]
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var selection: PlanSelection?
    @State private var editor: PlanEditorMode?
    @State private var eventToEdit: CalendarEventInfo?
    @State private var eventBlock: PlanBlock?
    @State private var scroll = ScrollPosition(edge: .top)

    init(day: Binding<Date>, clock: DayClock, path: Binding<[PlanRoute]>) {
        self._day = day
        self.clock = clock
        self._path = path
        let range = clock.range(for: day.wrappedValue)
        let s = range.start.addingTimeInterval(-86400 * 1.5), e = range.end
        _blocks = Query(filter: #Predicate<PlanBlock> { $0.start < e && $0.end > s }, sort: \PlanBlock.start)
    }

    private var today: Date { clock.logicalDay(for: Date()) }
    private var range: DateInterval { clock.range(for: day) }
    private var metrics: TimelineMetrics { TimelineMetrics(range: range, hourHeight: 52) }

    private var events: [CalendarEventInfo] {
        (prefsList.first?.showCalendarEvents ?? false) ? calendarService.events(in: range) : []
    }

    private var items: [PlanItem] {
        PlanResolver.items(day: day, clock: clock, blocks: blocks, timetables: timetables, events: events, links: links)
    }

    private var dayLabel: String {
        let diff = DayClock.calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case 0: return "오늘 계획"
        case 1: return "내일 계획"
        case -1: return "어제 계획"
        default: return "\(Fmt.monthDay(day)) 계획"
        }
    }

    var body: some View {
        let items = self.items
        let active = PlanResolver.activeTimetable(for: day, in: timetables)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { day = DayClock.addDays(-1, to: day) } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("전날")
                    Button { day = DayClock.addDays(1, to: day) } label: {
                        Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("다음 날")
                    Spacer()
                    Menu {
                        Section("이 날 적용되는 시간표: \(active?.name ?? "없음")") {
                            Button { path.append(.timetables) } label: { Label("시간표 관리", systemImage: "tablecells") }
                        }
                        Button { copyPreviousDay() } label: { Label("어제 계획 복사", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { clearDay() } label: { Label("이 날 직접 계획 모두 지우기", systemImage: "trash") }
                    } label: {
                        Label("템플릿", systemImage: "square.stack")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Palette.surface, in: .capsule)
                            .overlay(Capsule().strokeBorder(Palette.line))
                    }
                }
                .foregroundStyle(Palette.ink)
                .padding(.leading, -12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel).font(.footnote.weight(.medium)).foregroundStyle(Palette.inkSecondary)
                    Text(Fmt.dayTitle(day)).font(.title.bold())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let active {
                            OutlineChip(title: "\(active.name) 적용됨", symbol: "tablecells", filled: true) { path.append(.timetables) }
                        } else {
                            OutlineChip(title: "시간표 없음", symbol: "tablecells") { path.append(.timetables) }
                        }
                        OutlineChip(title: "어제 계획 복사") { copyPreviousDay() }
                        OutlineChip(title: events.isEmpty ? "캘린더 연동" : "캘린더 \(events.count)개", symbol: "calendar") { path.append(.calendar) }
                    }
                }
                .scrollClipDisabled()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            ScrollView {
                timeline(items)
                    .frame(height: metrics.totalHeight)
                    .padding(.top, 12)
                    .padding(.bottom, selection == nil ? 24 : 420)
            }
            .scrollPosition($scroll)
            .onAppear {
                let first = items.first?.start ?? range.start.addingTimeInterval(3 * 3600)
                scroll.scrollTo(y: max(0, metrics.y(first) - 60))
            }
        }
        .toastHost()
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(item: $editor, onDismiss: { selection = nil }) { mode in
            PlanEditorSheet(mode: mode, selection: $selection)
        }
        .sheet(item: $eventToEdit) { ev in
            EventEditSheet(info: ev, block: eventBlock)
        }
    }

    // MARK: 타임라인 · 드래그 선택

    @ViewBuilder
    private func timeline(_ items: [PlanItem]) -> some View {
        let m = metrics
        GeometryReader { geo in
            let colX: CGFloat = 60
            let colW = max(0, geo.size.width - colX - 16)
            ZStack(alignment: .topLeading) {
                HourGrid(metrics: m, labelWidth: 44, trailing: 16)

                Color.clear
                    .frame(width: colW, height: m.totalHeight)
                    .contentShape(.rect)
                    .offset(x: colX)
                    .gesture(selectionGesture(m).exclusively(before: tapGesture(m)))
                    .accessibilityLabel("빈 시간 — 눌러서 계획 추가")
                    .accessibilityAddTraits(.isButton)

                ForEach(items) { item in
                    let laneW = colW / CGFloat(max(1, item.laneCount))
                    let h = max(4, m.height(item.start, item.end) - 2)
                    Button {
                        open(item)
                    } label: {
                        TrackBlockView(style: .plan, title: item.title, subtitle: item.subtitle ?? Fmt.range(item.start, item.end),
                                       hex: item.colorHex, height: h, symbols: symbols(item))
                    }
                    .buttonStyle(.pressable)
                    .frame(width: max(0, laneW - (item.laneCount > 1 ? 2 : 0)), height: h)
                    .offset(x: colX + laneW * CGFloat(item.lane), y: m.y(item.start) + 1)
                    .accessibilityLabel("\(item.title), \(Fmt.range(item.start, item.end))")
                }

                if let sel = selection {
                    selectionOverlay(sel, m: m, colX: colX, colW: colW)
                }
            }
            .coordinateSpace(.named("planTL"))
        }
    }

    private func selectionGesture(_ m: TimelineMetrics) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("planTL")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let a = m.date(atY: drag.startLocation.y), b = m.date(atY: drag.location.y)
                let s = min(a, b), e = max(a, b)
                selection = PlanSelection(start: s, end: max(e, s.addingTimeInterval(15 * 60)))
            }
            .onEnded { value in
                guard case .second(true, _) = value, selection != nil else { return }
                editor = .new(day: day)
            }
    }

    private func tapGesture(_ m: TimelineMetrics) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named("planTL"))
            .onEnded { v in
                let s = m.date(atY: v.location.y - m.hourHeight / 4)
                selection = PlanSelection(start: s, end: min(s.addingTimeInterval(3600), range.end))
                editor = .new(day: day)
            }
    }

    private func selectionOverlay(_ sel: PlanSelection, m: TimelineMetrics, colX: CGFloat, colW: CGFloat) -> some View {
        let y0 = m.y(sel.start), y1 = m.y(sel.end)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Palette.ink.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .frame(width: colW, height: max(8, y1 - y0))
                .offset(x: colX, y: y0)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.hm(sel.start)) – \(Fmt.hm(sel.end))").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(Fmt.duration(Int(sel.end.timeIntervalSince(sel.start) / 60))) · 15분 단위")
                    .font(.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(Palette.ground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.ink, in: .rect(cornerRadius: 12))
            .offset(x: colX + 36, y: y0 + 18)
            .allowsHitTesting(false)

            handle
                .offset(x: colX + 4, y: y0 - 22)
                .gesture(DragGesture(coordinateSpace: .named("planTL")).onChanged { v in
                    let d = m.date(atY: v.location.y)
                    if d < sel.end.addingTimeInterval(-15 * 60) { selection?.start = d }
                })
                .accessibilityLabel("시작 시각 조절")
            handle
                .offset(x: colX + colW - 48, y: y1 - 22)
                .gesture(DragGesture(coordinateSpace: .named("planTL")).onChanged { v in
                    let d = m.date(atY: v.location.y)
                    if d > sel.start.addingTimeInterval(15 * 60) { selection?.end = d }
                })
                .accessibilityLabel("끝 시각 조절")
        }
    }

    private var handle: some View {
        Circle()
            .fill(Palette.surface)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
            .frame(width: 13, height: 13)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }

    private func symbols(_ item: PlanItem) -> [String] {
        switch item.kind {
        case .calendar: return ["calendar"]
        case .timetable: return ["repeat"]
        case .todo: return ["checklist"]
        case .manual: return item.hasOverlap ? ["square.on.square"] : []
        }
    }

    private func open(_ item: PlanItem) {
        if item.kind == .calendar, let ev = item.event {
            eventBlock = item.block
            eventToEdit = ev
        } else {
            editor = .edit(item)
        }
    }

    // MARK: 동작

    private func copyPreviousDay() {
        let prev = DayClock.addDays(-1, to: day)
        let prevRange = clock.range(for: prev)
        let source = DataStore.plans(in: prevRange, ctx: ctx).filter { ($0.source == .manual || $0.source == .todo) && !$0.isCancelled && $0.start >= prevRange.start }
        guard !source.isEmpty else {
            toasts.show("어제 직접 넣은 계획이 없어요", symbol: "info.circle")
            return
        }
        let key = DayClock.dayKey(day)
        var created: [PlanBlock] = []
        for b in source {
            let n = DataStore.makePlan(detail: b.detail, start: b.start.addingTimeInterval(86400), end: b.end.addingTimeInterval(86400),
                                       source: .manual, dayKey: key, ctx: ctx)
            n.askWhenDone = b.askWhenDone
            created.append(n)
        }
        DataStore.save(ctx)
        toasts.show("어제 계획 \(created.count)개를 복사했어요", symbol: "doc.on.doc") {
            for n in created { ctx.delete(n) }
            DataStore.save(ctx)
        }
    }

    private func clearDay() {
        let targets = blocks.filter { ($0.source == .manual || $0.source == .todo) && $0.start >= range.start && $0.start < range.end }
        for b in targets { ctx.delete(b) }
        DataStore.save(ctx)
        toasts.show("이 날의 직접 계획 \(targets.count)개를 지웠어요", symbol: "trash")
    }
}
