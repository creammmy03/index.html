import EventKit
import SwiftData
import SwiftUI

/// 08 · 반복 일정 → 시간표
struct TimetableConvertSheet: View {
    let preferred: Timetable?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]

    struct Candidate: Identifiable {
        let id: String
        let detail: ActivityDetail?
        let title: String
        let weekdays: [Int]
        let startMinute: Int
        let endMinute: Int
        let fromCalendar: Bool
        let calendarTitle: String?
        let blocks: [PlanBlock]
        let event: CalendarEventInfo?
    }

    @State private var candidates: [Candidate] = []
    @State private var selected: Set<String> = []
    @State private var targetID: UUID?
    @State private var deleteOriginals = true
    @State private var loaded = false
    @State private var pickDetailFor: String?
    @State private var overrides: [String: ActivityDetail] = [:]

    private var target: Timetable? { timetables.first { $0.id == targetID } ?? preferred ?? timetables.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidates.isEmpty ? "반복되는 일정을 찾지 못했어요" : "반복되는 일정 \(candidates.count)개를 찾았어요")
                            .font(.title3.bold())
                        Text("시간표로 옮기면 따로 흩어진 반복 일정을 한 곳에서 고치고, 시간표마다 다르게 쓸 수 있어요.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "옮길 일정").padding(.bottom, 6)
                            ForEach(candidates) { c in
                                candidateRow(c)
                                if c.id != candidates.last?.id { Divider() }
                            }
                        }
                        .padding(14)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))

                        VStack(spacing: 0) {
                            HStack {
                                Text("넣을 시간표")
                                Spacer()
                                Menu {
                                    ForEach(timetables) { t in
                                        Button(t.name) { targetID = t.id }
                                    }
                                    Button("새 시간표") {
                                        let t = Timetable(name: "새 시간표", isActive: timetables.isEmpty, sortOrder: timetables.count)
                                        ctx.insert(t)
                                        targetID = t.id
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(target?.name ?? "새 시간표")
                                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                                    }
                                    .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            Divider().padding(.leading, 14)
                            Toggle("옮긴 뒤 원래 반복 일정 지우기", isOn: $deleteOriginals)
                                .tint(Palette.ink)
                                .padding(.horizontal, 14).frame(minHeight: 50)
                        }
                        .background(Palette.surface, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))

                        Text("지난 기록은 그대로 남고, 오늘 이후 계획만 시간표에서 만들어져요.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("\(selected.count)개를 시간표로 옮기기") { convert() }
                    .buttonStyle(.primary)
                    .disabled(selected.isEmpty || !selectedHaveDetails)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
            .navigationTitle("시간표로 옮기기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .sheet(item: Binding(get: { pickDetailFor.map { IDBox(id: $0) } }, set: { pickDetailFor = $0?.id })) { box in
                DetailPickerSheet(title: "기록될 곳", confirmTitle: "지정", initial: overrides[box.id]) { d in overrides[box.id] = d }
            }
        }
        .appSheet([.large])
        .onAppear(perform: load)
    }

    struct IDBox: Identifiable { let id: String }

    private var selectedHaveDetails: Bool {
        candidates.filter { selected.contains($0.id) }.allSatisfy { (overrides[$0.id] ?? $0.detail) != nil }
    }

    private func candidateRow(_ c: Candidate) -> some View {
        let on = selected.contains(c.id)
        let detail = overrides[c.id] ?? c.detail
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if on { selected.remove(c.id) } else { selected.insert(c.id) }
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(on ? Palette.ink : Palette.inkTertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    pickDetailFor = c.id
                } label: {
                    HStack(spacing: 6) {
                        if let d = detail { ColorDot(hex: d.colorHex) }
                        Text(detail?.pathName ?? "\(c.title) · 기록될 곳 지정").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Palette.ink)
                }
                Text("\(Fmt.weekdays(c.weekdays)) \(Fmt.minuteLabel(c.startMinute))–\(Fmt.minuteLabel(c.endMinute)) · \(c.fromCalendar ? "캘린더 ‘\(c.calendarTitle ?? "")’" : "반복 계획")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkSecondary)
                if c.fromCalendar {
                    Text("캘린더 일정은 캘린더에서 관리하는 걸 추천해요").font(.caption2).foregroundStyle(Palette.divergeInk)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        targetID = (preferred ?? PlanResolver.activeTimetable(for: Date(), in: timetables) ?? timetables.first)?.id
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-28 * 86400), end: now.addingTimeInterval(28 * 86400))
        var found: [Candidate] = []

        // 직접 넣은 계획 중 같은 세부내역 · 같은 시각이 여러 주에 반복되는 것
        let manual = DataStore.plans(in: window, ctx: ctx).filter { $0.source == .manual && !$0.isCancelled }
        var groups: [String: [PlanBlock]] = [:]
        for b in manual {
            let key = "\(b.detail?.id.uuidString ?? "-")|\(DayClock.minuteOfDay(b.start))|\(DayClock.minuteOfDay(b.end))"
            groups[key, default: []].append(b)
        }
        for (key, blocks) in groups {
            let weeks = Set(blocks.map { DayClock.dayKey(DayClock.weekStart(for: $0.start)) })
            guard blocks.count >= 3, weeks.count >= 2, let first = blocks.first else { continue }
            let weekdays = Array(Set(blocks.map { DayClock.weekday($0.start) }))
            let s = DayClock.minuteOfDay(first.start)
            var e = DayClock.minuteOfDay(first.end)
            if e <= s { e += 1440 }
            found.append(Candidate(id: "pb:" + key, detail: first.detail, title: first.detail?.fullName ?? "계획",
                                   weekdays: weekdays, startMinute: s, endMinute: e, fromCalendar: false,
                                   calendarTitle: nil, blocks: blocks, event: nil))
        }

        // 캘린더의 반복 일정
        let future = DateInterval(start: now, end: now.addingTimeInterval(28 * 86400))
        var byExternal: [String: [CalendarEventInfo]] = [:]
        for ev in calendarService.events(in: future) where ev.isRecurring {
            byExternal[ev.externalID, default: []].append(ev)
        }
        for (ext, evs) in byExternal {
            guard let first = evs.first else { continue }
            let link = links.first { $0.calendarKey == first.calendarKey }
            if link?.mode == .ignore { continue }
            let s = DayClock.minuteOfDay(first.start)
            var e = DayClock.minuteOfDay(first.end)
            if e <= s { e += 1440 }
            found.append(Candidate(id: "ek:" + ext, detail: link?.detail, title: first.title,
                                   weekdays: Array(Set(evs.map { DayClock.weekday($0.start) })), startMinute: s, endMinute: e,
                                   fromCalendar: true, calendarTitle: first.calendarTitle, blocks: [], event: first))
        }
        candidates = found.sorted { ($0.fromCalendar ? 1 : 0, $0.startMinute) < ($1.fromCalendar ? 1 : 0, $1.startMinute) }
        selected = Set(candidates.filter { !$0.fromCalendar }.map(\.id))
    }

    private func convert() {
        let tt = target ?? {
            let t = Timetable(name: "평일 기본", isActive: true, sortOrder: timetables.count)
            ctx.insert(t)
            return t
        }()
        let now = Date()
        var moved = 0
        for c in candidates where selected.contains(c.id) {
            guard let detail = overrides[c.id] ?? c.detail else { continue }
            for wd in c.weekdays {
                DataStore.makeSlot(in: tt, detail: detail, weekday: wd, startMinute: c.startMinute, endMinute: c.endMinute, place: nil, ctx: ctx)
            }
            moved += 1
            guard deleteOriginals else { continue }
            if c.fromCalendar, let info = c.event, let ev = calendarService.event(for: info) {
                try? calendarService.remove(ev, span: .futureEvents)
            } else {
                for b in c.blocks where b.start >= now { ctx.delete(b) }
            }
        }
        DataStore.save(ctx)
        toasts.show("\(moved)개를 ‘\(tt.name)’에 옮겼어요", symbol: "tablecells")
        dismiss()
    }
}
