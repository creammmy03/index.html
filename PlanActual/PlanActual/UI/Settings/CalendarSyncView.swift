import EventKit
import SwiftData
import SwiftUI

/// 12 · 캘린더 연동 · 카테고리 지정
struct CalendarSyncView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query private var links: [CalendarLink]
    @State private var assigning: CalendarRef?

    struct CalendarRef: Identifiable {
        let id: String
        let title: String
        let account: String
        let colorHex: String
    }

    private var showEvents: Bool { prefsList.first?.showCalendarEvents ?? false }

    var body: some View {
        List {
            if !calendarService.hasEventAccess {
                Section {
                    PermissionCard(
                        title: calendarService.eventAccessDenied ? "캘린더 접근이 꺼져 있어요" : "캘린더를 연결해요",
                        message: "일정을 계획 트랙에 보여주고, 앱에서 고친 일정을 캘린더에도 저장해요. 캘린더 없이도 앱은 동작해요.",
                        buttonTitle: calendarService.eventAccessDenied ? "설정 열기" : "연결하기"
                    ) {
                        if calendarService.eventAccessDenied { calendarService.openSettings() }
                        else {
                            Task {
                                if await calendarService.requestEventAccess() { setShow(true) }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Toggle(isOn: Binding(get: { showEvents }, set: { setShow($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("계획 트랙에 캘린더 일정 표시")
                            Text("양방향 · 앱에서 고치면 캘린더에도 반영돼요")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .tint(Palette.ink)
                }
                Section {
                    ForEach(refs) { ref in
                        Button { assigning = ref } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: ref.colorHex)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ref.title).foregroundStyle(Palette.ink)
                                    Text(ref.account).font(.caption).foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer()
                                Text(mappingText(ref)).font(.footnote).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkTertiary)
                            }
                        }
                    }
                } header: {
                    Text("캘린더마다 카테고리 › 세부내역 지정")
                } footer: {
                    Text("지정하지 않은 캘린더의 일정은 회색으로 보이고 일치율에서는 ‘미분류’로 셈해요.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("캘린더 연동")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { calendarService.refreshStatus() }
        .sheet(item: $assigning) { ref in CalendarAssignSheet(ref: ref) }
    }

    private var refs: [CalendarRef] {
        calendarService.eventCalendars().map { cal in
            let comps = cal.cgColor?.components ?? [0.5, 0.5, 0.5]
            let hex = comps.count >= 3 ? RGB(r: comps[0] * 255, g: comps[1] * 255, b: comps[2] * 255).hex : "#8A8A85"
            return CalendarRef(id: CalendarService.key(for: cal), title: cal.title,
                               account: CalendarService.accountName(for: cal), colorHex: hex)
        }
    }

    private func mappingText(_ ref: CalendarRef) -> String {
        guard let link = links.first(where: { $0.calendarKey == ref.id }) else { return "지정 안 함" }
        if link.mode == .ignore { return "가져오지 않음" }
        return link.detail?.pathName ?? "지정 안 함"
    }

    private func setShow(_ on: Bool) {
        let p = DataStore.preferences(ctx)
        p.showCalendarEvents = on
        p.updatedAt = Date()
        DataStore.save(ctx)
    }
}

/// 12 내부 · 캘린더별 지정 (medium)
struct CalendarAssignSheet: View {
    let ref: CalendarSyncView.CalendarRef
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var links: [CalendarLink]
    @State private var importIt = true
    @State private var detail: ActivityDetail?
    @State private var loaded = false

    private var link: CalendarLink? { links.first { $0.calendarKey == ref.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("이 캘린더의 일정은 모두 하나의 세부내역으로 기록돼요. 일정 제목은 메모로 남아요.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Picker("가져오기", selection: $importIt) {
                        Text("가져오기").tag(true)
                        Text("가져오지 않음").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if importIt {
                        DetailPicker(selection: $detail)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("저장") { save() }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
            .navigationTitle("‘\(ref.title)’ 캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
        .appSheet([.medium, .large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            importIt = link?.mode != .ignore
            detail = link?.detail
        }
    }

    private func save() {
        let l = link ?? {
            let n = CalendarLink(calendarKey: ref.id, calendarTitle: ref.title, mode: .importAs)
            ctx.insert(n)
            return n
        }()
        l.mode = importIt ? .importAs : .ignore
        l.detail = importIt ? detail : nil
        l.calendarTitle = ref.title
        l.updatedAt = Date()
        DataStore.save(ctx)
        dismiss()
    }
}

/// 13 · 캘린더 일정 편집 · 삭제 — 저장하면 캘린더에 바로 반영
struct EventEditSheet: View {
    let info: CalendarEventInfo
    let block: PlanBlock?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var calendarKey = ""
    @State private var detailOverride: ActivityDetail?
    @State private var showDetailPicker = false
    @State private var askSpan: SpanAction?
    @State private var loaded = false

    enum SpanAction: Identifiable {
        case save, delete
        var id: Int { self == .save ? 0 : 1 }
    }

    private var event: EKEvent? { calendarService.event(for: info) }
    private var calendarLinkDetail: ActivityDetail? { links.first { $0.calendarKey == calendarKey }?.detail }
    private var recordedDetail: ActivityDetail? { detailOverride ?? calendarLinkDetail }

    /// 이 일정 때문에 그날 숨겨지는 시간표 칸
    private var skippedSlots: [(TimetableSlot, Date, Date)] {
        let clock = DayClock(prefsList.first)
        let day = clock.logicalDay(for: start)
        guard let tt = PlanResolver.activeTimetable(for: day, in: timetables) else { return [] }
        return (tt.slots ?? []).filter { $0.weekday == DayClock.weekday(day) }.compactMap { s in
            let ss = clock.date(on: day, minute: s.startMinute)
            let se = ss.addingTimeInterval(Double(s.durationMinutes) * 60)
            return ss < end && se > start ? (s, ss, se) : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $title)
                    DatePicker("날짜", selection: Binding(get: { start }, set: { moveDay(to: $0) }), displayedComponents: .date)
                    DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("종료", selection: $end, in: start.addingTimeInterval(300)..., displayedComponents: .hourAndMinute)
                }
                Section {
                    Picker("캘린더", selection: $calendarKey) {
                        ForEach(calendarService.writableCalendars(), id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(CalendarService.key(for: cal))
                        }
                    }
                    Button { showDetailPicker = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("기록될 곳").foregroundStyle(Palette.ink)
                                Text(detailOverride == nil ? "캘린더 설정을 따라요 · 이 일정만 바꿀 수 있어요" : "이 일정만 바꿨어요")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            if let d = recordedDetail { ColorDot(hex: d.colorHex) }
                            Text(recordedDetail?.pathName ?? "지정 안 함").foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    HStack {
                        Text("반복")
                        Spacer()
                        Text(info.isRecurring ? "반복 일정" : "반복 안 함").foregroundStyle(Palette.inkSecondary)
                    }
                }
                ForEach(skippedSlots, id: \.0.id) { slot, s, e in
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("이 날은 시간표 ‘\(slot.detail?.name ?? "")’를 건너뛰어요").font(.subheadline.weight(.semibold))
                            Text("\(Fmt.range(s, e))이 겹쳐요. 캘린더 일정이 시간표보다 우선이에요.")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Button("\(slot.detail?.name ?? "시간표 칸")를 다른 시간으로") { moveSlot(slot, s, e) }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        if info.isRecurring { askSpan = .delete } else { delete(span: .thisEvent) }
                    } label: {
                        Label("일정 삭제", systemImage: "trash")
                    }
                } footer: {
                    Text("저장하면 캘린더 ‘\(calendarService.calendar(forKey: calendarKey)?.title ?? info.calendarTitle)’에도 바로 반영돼요.")
                }
            }
            .tint(Palette.ink)
            .navigationTitle("일정 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        if info.isRecurring && timeOrTitleChanged { askSpan = .save } else { save(span: .thisEvent) }
                    }
                }
            }
            .confirmationDialog("반복 일정이에요", isPresented: Binding(get: { askSpan != nil }, set: { if !$0 { askSpan = nil } }), titleVisibility: .visible, presenting: askSpan) { action in
                Button("이 일정만") { action == .save ? save(span: .thisEvent) : delete(span: .thisEvent) }
                Button("이후 모두") { action == .save ? save(span: .futureEvents) : delete(span: .futureEvents) }
                Button("취소", role: .cancel) {}
            }
            .sheet(isPresented: $showDetailPicker) {
                DetailPickerSheet(title: "기록될 곳", message: "이 일정 하나만 다른 세부내역으로 기록해요.", confirmTitle: "바꾸기", initial: recordedDetail) { d in
                    detailOverride = d
                }
            }
        }
        .appSheet([.large])
        .onAppear(perform: load)
    }

    private var timeOrTitleChanged: Bool {
        title != info.title || start != info.start || end != info.end || calendarKey != info.calendarKey
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        title = info.title
        start = info.start
        end = info.end
        calendarKey = info.calendarKey
        if let b = block, b.detail?.id != links.first(where: { $0.calendarKey == info.calendarKey })?.detail?.id {
            detailOverride = b.detail
        }
    }

    private func moveDay(to date: Date) {
        let cal = DayClock.calendar
        let dayShift = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: date)).day ?? 0
        start = cal.date(byAdding: .day, value: dayShift, to: start) ?? start
        end = cal.date(byAdding: .day, value: dayShift, to: end) ?? end
    }

    private func save(span: EKSpan) {
        if timeOrTitleChanged {
            guard let ev = event else {
                toasts.show("캘린더에서 일정을 찾지 못했어요", symbol: "exclamationmark.triangle")
                return
            }
            ev.title = title
            ev.startDate = start
            ev.endDate = end
            if let cal = calendarService.calendar(forKey: calendarKey) { ev.calendar = cal }
            do {
                try calendarService.save(ev, span: span)
            } catch {
                toasts.show("캘린더에 저장하지 못했어요", symbol: "exclamationmark.triangle")
                return
            }
        }
        // 이 일정만 다른 세부내역으로 → PlanBlock(source: calendar)에 남겨요.
        if detailOverride != nil || block != nil {
            let clock = DayClock(prefsList.first)
            let dayKey = DayClock.dayKey(clock.logicalDay(for: start))
            let b = block ?? {
                let n = DataStore.makePlan(detail: nil, start: start, end: end, source: .calendar, dayKey: dayKey, ctx: ctx)
                n.ekExternalID = info.externalID
                return n
            }()
            b.detail = recordedDetail
            b.start = start
            b.end = end
            b.dayKey = dayKey
            b.title = title
            b.updatedAt = Date()
            DataStore.save(ctx)
        }
        dismiss()
    }

    private func delete(span: EKSpan) {
        guard let ev = event else { dismiss(); return }
        do {
            try calendarService.remove(ev, span: span)
            if let b = block { ctx.delete(b); DataStore.save(ctx) }
            toasts.show("일정을 지웠어요", symbol: "trash")
        } catch {
            toasts.show("캘린더에서 지우지 못했어요", symbol: "exclamationmark.triangle")
        }
        dismiss()
    }

    /// 겹친 시간표 칸을 일정이 끝난 직후로 그날만 옮겨요.
    private func moveSlot(_ slot: TimetableSlot, _ s: Date, _ e: Date) {
        let clock = DayClock(prefsList.first)
        let day = clock.logicalDay(for: s)
        let dayKey = DayClock.dayKey(day)
        let slotKey = "\(dayKey)|\(slot.id.uuidString)"
        let existing = DataStore.plans(in: DateInterval(start: s.addingTimeInterval(-86400), end: e.addingTimeInterval(86400)), ctx: ctx)
            .first { $0.slotKey == slotKey }
        let b = existing ?? {
            let n = DataStore.makePlan(detail: slot.detail, start: s, end: e, source: .timetable, dayKey: dayKey, ctx: ctx)
            n.slotKey = slotKey
            return n
        }()
        let dur = e.timeIntervalSince(s)
        b.start = end
        b.end = end.addingTimeInterval(dur)
        b.updatedAt = Date()
        DataStore.save(ctx)
        toasts.show("\(slot.detail?.name ?? "시간표 칸")를 \(Fmt.hm(end))로 옮겼어요", symbol: "arrow.down.to.line")
    }
}
