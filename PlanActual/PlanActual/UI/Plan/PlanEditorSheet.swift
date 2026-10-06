import SwiftData
import SwiftUI

enum PlanEditorMode: Identifiable {
    case new(day: Date)
    case edit(PlanItem)

    var id: String {
        switch self {
        case .new(let d): return "new-\(d.timeIntervalSince1970)"
        case .edit(let i): return i.key
        }
    }
}

/// 02 내부 · 활동 추가 / 고치기 (medium · large)
struct PlanEditorSheet: View {
    let mode: PlanEditorMode
    var selection: Binding<PlanSelection?>? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var detail: ActivityDetail?
    @State private var localStart = Date()
    @State private var localEnd = Date().addingTimeInterval(3600)
    @State private var repeatWeekly = false
    @State private var askWhenDone = true
    @State private var didLoad = false

    private var isNew: Bool { if case .new = mode { return true } else { return false } }
    private var editingItem: PlanItem? { if case .edit(let i) = mode { return i } else { return nil } }
    private var day: Date {
        switch mode {
        case .new(let d): return d
        case .edit(let i): return DayClock.day(fromKey: i.dayKey) ?? i.start
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { selection?.wrappedValue?.start ?? localStart },
                set: { v in
                    if let selection, selection.wrappedValue != nil, isNew { selection.wrappedValue?.start = v } else { localStart = v }
                })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { selection?.wrappedValue?.end ?? localEnd },
                set: { v in
                    if let selection, selection.wrappedValue != nil, isNew { selection.wrappedValue?.end = v } else { localEnd = v }
                })
    }

    private var start: Date { startBinding.wrappedValue }
    private var end: Date { endBinding.wrappedValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailPicker(selection: $detail)

                    VStack(spacing: 0) {
                        HStack {
                            Text("시간")
                            Spacer()
                            DatePicker("시작", selection: startBinding, displayedComponents: .hourAndMinute).labelsHidden()
                            Text("–").foregroundStyle(Palette.inkSecondary)
                            DatePicker("끝", selection: endBinding, in: start.addingTimeInterval(15 * 60)..., displayedComponents: .hourAndMinute).labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        Divider().padding(.leading, 14)
                        if isNew {
                            Toggle(isOn: $repeatWeekly) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("반복 · 시간표")
                                    Text(repeatWeekly ? "매주 \(Fmt.weekdayLong(day)) · ‘\(targetTimetableName)’에 추가" : "안 함")
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            Divider().padding(.leading, 14)
                        } else if let item = editingItem, item.kind == .timetable {
                            HStack {
                                Text("시간표 칸")
                                Spacer()
                                Text("이 날만 바꿔요").foregroundStyle(Palette.inkSecondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            Divider().padding(.leading, 14)
                        }
                        Toggle("끝나면 “했나요?” 묻기", isOn: $askWhenDone)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                    }
                    .font(.subheadline)
                    .background(Palette.surface, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                    .tint(Palette.ink)

                    if let item = editingItem {
                        deleteSection(item)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(isNew ? "\(Fmt.range(start, end))에 추가" : "저장") { save() }
                    .buttonStyle(.primary)
                    .disabled(detail == nil || end <= start)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
            .navigationTitle(isNew ? "활동 추가" : "계획 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
        .appSheet([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func deleteSection(_ item: PlanItem) -> some View {
        VStack(spacing: 8) {
            switch item.kind {
            case .timetable:
                Button("이 날만 지우기", role: .destructive) {
                    let b = DataStore.materialize(item, ctx: ctx)
                    b.isCancelled = true
                    DataStore.save(ctx)
                    toasts.show("이 날의 시간표 칸을 숨겼어요", symbol: "eye.slash") {
                        b.isCancelled = false
                        DataStore.save(ctx)
                    }
                    dismiss()
                }
                .buttonStyle(.secondary)
                if let slot = item.slot {
                    Button("시간표에서 이 칸 지우기", role: .destructive) {
                        ctx.delete(slot)
                        DataStore.save(ctx)
                        dismiss()
                    }
                    .buttonStyle(.secondary)
                }
            default:
                Button(role: .destructive) {
                    if let b = item.block {
                        let snapshot = (b.detail, b.start, b.end, b.sourceRaw, b.dayKey, b.askWhenDone)
                        ctx.delete(b)
                        DataStore.save(ctx)
                        toasts.show("계획을 지웠어요", symbol: "trash") {
                            let n = DataStore.makePlan(detail: snapshot.0, start: snapshot.1, end: snapshot.2,
                                                       source: PlanSource(rawValue: snapshot.3) ?? .manual, dayKey: snapshot.4, ctx: ctx)
                            n.askWhenDone = snapshot.5
                            DataStore.save(ctx)
                        }
                    }
                    dismiss()
                } label: {
                    Label("계획 지우기", systemImage: "trash")
                }
                .buttonStyle(.secondary)
            }
        }
        .foregroundStyle(Palette.destructive)
    }

    private var targetTimetableName: String {
        PlanResolver.activeTimetable(for: day, in: timetables)?.name ?? "기본 시간표"
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        askWhenDone = prefsList.first?.askWhenDone ?? true
        switch mode {
        case .new:
            if let sel = selection?.wrappedValue {
                localStart = sel.start
                localEnd = sel.end
            }
        case .edit(let item):
            detail = item.detail
            localStart = item.start
            localEnd = item.end
            askWhenDone = item.askWhenDone
        }
    }

    private func save() {
        guard let detail, end > start else { return }
        let dayKey = DayClock.dayKey(day)
        switch mode {
        case .new:
            if repeatWeekly {
                let tt = PlanResolver.activeTimetable(for: day, in: timetables) ?? {
                    let t = Timetable(name: "기본 시간표", isActive: true, sortOrder: timetables.count)
                    ctx.insert(t)
                    return t
                }()
                let startMin = DayClock.minuteOfDay(start)
                let dur = Int(end.timeIntervalSince(start) / 60)
                let slot = DataStore.makeSlot(in: tt, detail: detail, weekday: DayClock.weekday(day),
                                              startMinute: startMin, endMinute: startMin + dur, place: nil, ctx: ctx)
                toasts.show("매주 \(Fmt.weekdayLong(day)) 시간표에 넣었어요", symbol: "repeat") {
                    ctx.delete(slot)
                    DataStore.save(ctx)
                }
            } else {
                let b = DataStore.makePlan(detail: detail, start: start, end: end, source: .manual, dayKey: dayKey, ctx: ctx)
                b.askWhenDone = askWhenDone
                toasts.show("\(detail.fullName) · \(Fmt.range(start, end))", symbol: "plus") {
                    ctx.delete(b)
                    DataStore.save(ctx)
                }
            }
        case .edit(let item):
            let b = DataStore.materialize(item, ctx: ctx)
            b.detail = detail
            b.start = start
            b.end = end
            b.askWhenDone = askWhenDone
            b.updatedAt = Date()
        }
        DataStore.save(ctx)
        Task { await NotificationService.requestAuthorizationIfNeeded() }
        dismiss()
    }
}
