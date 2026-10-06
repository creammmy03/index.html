import SwiftData
import SwiftUI

enum SlotEditTarget: Identifiable {
    case new(Timetable)
    case edit(TimetableSlot)
    var id: String {
        switch self {
        case .new(let t): return "new-\(t.id)"
        case .edit(let s): return s.id.uuidString
        }
    }
}

/// 07 · 시간표 여러 개 · 템플릿
struct TimetablesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @State private var selectedID: UUID?
    @State private var slotTarget: SlotEditTarget?
    @State private var editingTimetable: Timetable?
    @State private var showConvert = false

    private var selected: Timetable? {
        timetables.first { $0.id == selectedID } ?? PlanResolver.activeTimetable(for: Date(), in: timetables) ?? timetables.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(timetables) { t in
                            let status = PlanResolver.status(of: t, today: Date(), all: timetables)
                            let on = t.id == selected?.id
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedID = t.id }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(t.name).font(.subheadline.weight(.semibold))
                                        Text(status.label)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(status == .applied ? (on ? Palette.ground.opacity(0.2) : Palette.ink.opacity(0.08)) : Color.clear, in: .capsule)
                                    }
                                    Text(PlanResolver.periodText(t)).font(.caption).opacity(0.75)
                                }
                                .foregroundStyle(on ? Palette.ground : Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(on ? Palette.ink : Palette.surface, in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.clear : Palette.line))
                            }
                            .buttonStyle(.pressable)
                        }
                        Button { createTimetable() } label: {
                            Image(systemName: "plus")
                                .frame(width: 48, height: 48)
                                .background(Palette.surface, in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
                        }
                        .buttonStyle(.pressable)
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("시간표 추가")
                    }
                }
                .scrollClipDisabled()

                if let t = selected {
                    TimetableGrid(timetable: t) { slot in slotTarget = .edit(slot) }
                        .id(t.id)
                        .transition(.opacity)

                    let slots = t.slots ?? []
                    let weekly = slots.reduce(0) { $0 + $1.durationMinutes }
                    let activities = Set(slots.compactMap { $0.detail?.id }).count
                    HStack {
                        Text("반복 활동 \(activities)개 · 주 \(Fmt.duration(weekly))").font(.footnote.weight(.medium))
                        Spacer()
                        Text("캘린더와 겹치면 캘린더 우선").font(.caption).foregroundStyle(Palette.inkSecondary)
                    }

                    HStack(spacing: 8) {
                        Button { slotTarget = .new(t) } label: { Label("칸 추가", systemImage: "plus") }
                            .buttonStyle(.primary)
                        Button { editingTimetable = t } label: { Label("적용 기간 · 요일", systemImage: "calendar") }
                            .buttonStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button { duplicate(t) } label: { Label("복제해서 새로 만들기", systemImage: "plus.square.on.square") }
                            .buttonStyle(.secondary)
                        Button { showConvert = true } label: { Label("반복 일정 가져오기", systemImage: "repeat") }
                            .buttonStyle(.secondary)
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("시간표가 없어요").font(.headline)
                            Text("매주 반복하는 활동을 시간표로 만들어두면 매일 계획에 자동으로 깔려요. 캘린더 일정과 겹치는 칸은 그날만 숨겨요.")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                            Button("시간표 만들기") { createTimetable() }.buttonStyle(.primary)
                            Button("반복 일정에서 만들기") { showConvert = true }.buttonStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.ground)
        .navigationTitle("시간표")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $slotTarget) { t in SlotEditSheet(target: t) }
        .sheet(item: $editingTimetable) { t in TimetableEditSheet(timetable: t) }
        .sheet(isPresented: $showConvert) { TimetableConvertSheet(preferred: selected) }
    }

    private func createTimetable() {
        let t = Timetable(name: timetables.isEmpty ? "평일 기본" : "새 시간표", isActive: timetables.isEmpty, sortOrder: timetables.count)
        ctx.insert(t)
        DataStore.save(ctx)
        selectedID = t.id
        editingTimetable = t
    }

    private func duplicate(_ t: Timetable) {
        let n = Timetable(name: "\(t.name) 복사본", isActive: false, sortOrder: timetables.count)
        ctx.insert(n)
        for s in t.slots ?? [] {
            DataStore.makeSlot(in: n, detail: s.detail, weekday: s.weekday, startMinute: s.startMinute, endMinute: s.endMinute, place: s.place, ctx: ctx)
        }
        DataStore.save(ctx)
        selectedID = n.id
        toasts.show("‘\(n.name)’을 만들었어요 · 적용 기간을 정해주세요", symbol: "plus.square.on.square")
        editingTimetable = n
    }
}

/// 시간표 격자 — 1시간 30pt · 평일 5열(주말 칸이 있으면 7열)
struct TimetableGrid: View {
    let timetable: Timetable
    let onTap: (TimetableSlot) -> Void

    var body: some View {
        let slots = timetable.slots ?? []
        let hasWeekend = slots.contains { $0.weekday == 1 || $0.weekday == 7 }
        let weekdays = hasWeekend ? [2, 3, 4, 5, 6, 7, 1] : [2, 3, 4, 5, 6]
        let startHour = min(8, (slots.map(\.startMinute).min() ?? 480) / 60)
        let endHour = max(22, Int(ceil(Double(slots.map(\.endMinute).max() ?? 1320) / 60)))
        let base = DayClock.calendar.startOfDay(for: Date())
        let range = DateInterval(start: base.addingTimeInterval(Double(startHour) * 3600), end: base.addingTimeInterval(Double(endHour) * 3600))
        let m = TimelineMetrics(range: range, hourHeight: 30, topInset: 6)

        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Color.clear.frame(width: 26)
                ForEach(weekdays, id: \.self) { wd in
                    Text(Fmt.weekdaySymbols[wd - 1])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    ForEach(Array(m.hourMarks.enumerated()), id: \.offset) { _, mark in
                        Text(mark.label).font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                            .offset(y: mark.y - 6)
                    }
                }
                .frame(width: 26, height: m.totalHeight, alignment: .topTrailing)
                ForEach(weekdays, id: \.self) { wd in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(m.hourMarks.enumerated()), id: \.offset) { _, mark in
                                Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1).offset(y: mark.y)
                            }
                            ForEach(slots.filter { $0.weekday == wd }) { s in
                                let st = base.addingTimeInterval(Double(s.startMinute) * 60)
                                let en = base.addingTimeInterval(Double(s.endMinute) * 60)
                                let h = max(4, m.height(st, en) - 2)
                                Button { onTap(s) } label: {
                                    TrackBlockView(style: .plan, title: s.detail?.name ?? "미지정",
                                                   subtitle: s.place, hex: s.detail?.colorHex ?? "#52606F",
                                                   height: h, compact: true)
                                }
                                .buttonStyle(.pressable)
                                .frame(width: geo.size.width, height: h)
                                .offset(y: m.y(st) + 1)
                                .accessibilityLabel("\(Fmt.weekdaySymbols[wd - 1])요일 \(s.detail?.fullName ?? ""), \(Fmt.minuteLabel(s.startMinute))–\(Fmt.minuteLabel(s.endMinute))")
                            }
                        }
                    }
                    .frame(height: m.totalHeight)
                }
            }
        }
        .padding(10)
        .background(Palette.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
    }
}

/// 적용 기간 · 이름 · 켜기
struct TimetableEditSheet: View {
    @Bindable var timetable: Timetable
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름", text: $timetable.name)
                    Toggle("사용", isOn: $timetable.isActive)
                } footer: {
                    Text("기간이 겹치면 기간이 더 짧은 시간표가 그날 적용돼요. 예: ‘평일 기본’ 위에 ‘시험 기간’")
                }
                Section("적용 기간") {
                    Toggle("시작일", isOn: Binding(get: { timetable.startDate != nil }, set: { timetable.startDate = $0 ? DayClock.calendar.startOfDay(for: Date()) : nil }))
                    if timetable.startDate != nil {
                        DatePicker("시작", selection: Binding(get: { timetable.startDate ?? Date() }, set: { timetable.startDate = $0 }), displayedComponents: .date)
                    }
                    Toggle("종료일", isOn: Binding(get: { timetable.endDate != nil }, set: { timetable.endDate = $0 ? DayClock.addDays(30, to: timetable.startDate ?? Date()) : nil }))
                    if timetable.endDate != nil {
                        DatePicker("종료", selection: Binding(get: { timetable.endDate ?? Date() }, set: { timetable.endDate = $0 }), in: (timetable.startDate ?? .distantPast)..., displayedComponents: .date)
                    }
                }
                Section {
                    Button("시간표 지우기", role: .destructive) { confirmDelete = true }
                }
            }
            .tint(Palette.ink)
            .navigationTitle("시간표")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        timetable.updatedAt = Date()
                        DataStore.save(ctx)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("‘\(timetable.name)’을 지울까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("지우기", role: .destructive) {
                    ctx.delete(timetable)
                    DataStore.save(ctx)
                    dismiss()
                }
            } message: {
                Text("지난 날 저장된 계획은 그대로 남아요.")
            }
        }
        .appSheet([.medium, .large])
    }
}

/// 시간표 칸 추가 · 편집
struct SlotEditSheet: View {
    let target: SlotEditTarget
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ActivityDetail?
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var start = Date()
    @State private var end = Date()
    @State private var place = ""
    @State private var loaded = false

    private var base: Date { DayClock.calendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailPicker(selection: $detail)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "요일")
                        HStack(spacing: 6) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                let on = weekdays.contains(wd)
                                Button {
                                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                                } label: {
                                    Text(Fmt.weekdaySymbols[wd - 1])
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(on ? Palette.ground : Palette.ink)
                                        .background(on ? Palette.ink : Palette.ground, in: .rect(cornerRadius: 12))
                                }
                                .buttonStyle(.pressable)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Text("시간")
                            Spacer()
                            DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                            Text("–")
                            DatePicker("끝", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 50)
                        Divider().padding(.leading, 14)
                        TextField("장소 (선택)", text: $place)
                            .padding(.horizontal, 14).frame(minHeight: 50)
                    }
                    .background(Palette.surface, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))

                    if case .edit(let slot) = target {
                        Button(role: .destructive) {
                            ctx.delete(slot)
                            DataStore.save(ctx)
                            dismiss()
                        } label: {
                            Label("이 칸 지우기", systemImage: "trash")
                        }
                        .buttonStyle(.secondary)
                        .foregroundStyle(Palette.destructive)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("저장") { save() }
                    .buttonStyle(.primary)
                    .disabled(detail == nil || weekdays.isEmpty || minutes(end) <= minutes(start))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
            .navigationTitle(isNew ? "시간표 칸 추가" : "시간표 칸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
        .appSheet([.large])
        .onAppear(perform: load)
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private func minutes(_ d: Date) -> Int { DayClock.minuteOfDay(d) / 5 * 5 }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new:
            start = base.addingTimeInterval(9 * 3600)
            end = base.addingTimeInterval(10 * 3600)
        case .edit(let s):
            detail = s.detail
            weekdays = [s.weekday]
            start = base.addingTimeInterval(Double(s.startMinute) * 60)
            end = base.addingTimeInterval(Double(s.endMinute) * 60)
            place = s.place ?? ""
        }
    }

    private func save() {
        guard let detail else { return }
        let s = minutes(start), e = minutes(end)
        let placeValue = place.trimmingCharacters(in: .whitespaces).isEmpty ? nil : place
        switch target {
        case .new(let tt):
            for wd in weekdays {
                DataStore.makeSlot(in: tt, detail: detail, weekday: wd, startMinute: s, endMinute: e, place: placeValue, ctx: ctx)
            }
        case .edit(let slot):
            let days = weekdays.sorted()
            slot.detail = detail
            slot.weekday = days.first ?? slot.weekday
            slot.startMinute = s
            slot.endMinute = e
            slot.place = placeValue
            slot.updatedAt = Date()
            if let tt = slot.timetable {
                for wd in days.dropFirst() {
                    DataStore.makeSlot(in: tt, detail: detail, weekday: wd, startMinute: s, endMinute: e, place: placeValue, ctx: ctx)
                }
            }
        }
        DataStore.save(ctx)
        dismiss()
    }
}
