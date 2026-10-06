import SwiftData
import SwiftUI

/// 01 내부 · “했나요?” 확인 시트 (medium)
struct ConfirmSheet: View {
    let item: PlanItem
    let spans: [ActualSpan]
    let onPick: (Confirmation, ActivityDetail?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showOther = false
    @State private var showEventEdit = false
    @State private var showPlanEdit = false

    private var recorded: [(name: String, minutes: Int, categoryID: UUID)] {
        var map: [UUID: (String, Int)] = [:]
        var order: [UUID] = []
        for s in spans {
            let a = max(s.start, item.start), b = min(s.end, item.end)
            guard b > a else { continue }
            let key = s.categoryID ?? DayAnalysis.uncategorized
            if map[key] == nil { order.append(key) }
            map[key] = (s.detail?.category?.name ?? "미분류", (map[key]?.1 ?? 0) + Int(b.timeIntervalSince(a) / 60))
        }
        return order.compactMap { k in map[k].map { (name: $0.0, minutes: $0.1, categoryID: k) } }
    }

    private var note: String {
        if item.start > Date() { return "아직 시작 전이에요." }
        let r = recorded.filter { $0.minutes > 0 }
        var text = r.isEmpty ? "이 시간에 기록이 없어요." : "실제 기록: " + r.map { "\($0.name) \(Fmt.duration($0.minutes))" }.joined(separator: " · ")
        if item.kind == .calendar { text = "캘린더에서 가져온 일정이에요. " + text }
        if item.kind == .timetable { text = "시간표 ‘\(item.slot?.timetable?.name ?? "")’의 칸이에요. " + text }
        return text
    }

    private var sameCategoryMinutes: Int {
        recorded.filter { $0.categoryID == (item.categoryID ?? DayAnalysis.uncategorized) }.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ColorDot(hex: item.colorHex)
                            Text(item.title).font(.title3.bold()).lineLimit(2)
                        }
                        Text("\(Fmt.range(item.start, item.end)) · 계획 \(Fmt.duration(item.minutes))")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.ground, in: .rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("실제로 어떻게 보냈나요?")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 2)
                            .padding(.bottom, 8)
                        option(.done)
                        option(.partial, trailing: sameCategoryMinutes > 0 ? "\(Fmt.duration(sameCategoryMinutes)) 기록됨" : nil)
                        option(.other)
                        option(.skip)
                    }

                    HStack(spacing: 10) {
                        if item.kind == .calendar && item.event != nil {
                            Button("일정 편집") { showEventEdit = true }.buttonStyle(.secondary)
                        } else {
                            Button("계획 고치기") { showPlanEdit = true }.buttonStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showOther) {
                OtherActivityPicker(initial: nil) { d in
                    onPick(.other, d)
                    dismiss()
                }
            }
        }
        .appSheet([.medium, .large])
        .sheet(isPresented: $showEventEdit) {
            if let ev = item.event { EventEditSheet(info: ev, block: item.block) }
        }
        .sheet(isPresented: $showPlanEdit) {
            PlanEditorSheet(mode: .edit(item))
        }
    }

    private func option(_ kind: Confirmation, trailing: String? = nil) -> some View {
        let selected = item.confirmation == kind
        return Button {
            if kind == .other {
                showOther = true
            } else {
                onPick(kind, nil)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                Text(kind.label).font(.body.weight(.medium))
                Spacer()
                if let trailing {
                    Text(trailing).font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
                if selected { Image(systemName: "checkmark.circle.fill") }
                if kind == .other { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.inkTertiary) }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(selected ? Palette.ground : Color.clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}

/// “다른 걸 했어요” — 무엇을 했는지 고르기
struct OtherActivityPicker: View {
    let initial: ActivityDetail?
    let onPick: (ActivityDetail) -> Void
    @State private var selection: ActivityDetail?

    var body: some View {
        ScrollView {
            DetailPicker(selection: $selection)
                .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("이걸로 기록") {
                if let s = selection { onPick(s) }
            }
            .buttonStyle(.primary)
            .disabled(selection == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle("무엇을 했나요?")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selection == nil { selection = initial } }
    }
}

// MARK: - 타이머 막대

/// 높이 60 · 모서리 20 · 탭 바 위 12pt · 정지 버튼 44pt
struct TimerBar: View {
    let currentPlan: PlanItem?
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<ActualRecord> { $0.end == nil }, sort: \ActualRecord.start) private var running: [ActualRecord]
    @State private var showStart = false
    @State private var feedback = 0

    var body: some View {
        let r = running.last
        HStack(spacing: 12) {
            if let r {
                ColorDot(hex: r.detail?.colorHex ?? "#52606F")
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.detail?.fullName ?? "기록 중")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(status(for: r))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(r.start, style: .timer)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 64, alignment: .trailing)
                Button {
                    DataStore.stopTimer(r, ctx: ctx)
                    feedback += 1
                } label: {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.ground).frame(width: 12, height: 12)
                        .frame(width: 44, height: 44)
                        .background(Palette.ink, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("타이머 정지")
            } else {
                Image(systemName: "record.circle")
                    .font(.title3)
                    .foregroundStyle(Palette.inkSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("지금 하는 일 기록하기").font(.subheadline.weight(.semibold))
                    Text(currentPlan.map { "계획: \($0.title)" } ?? "타이머로 실제 시간을 남겨요")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    showStart = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.body)
                        .foregroundStyle(Palette.ground)
                        .frame(width: 44, height: 44)
                        .background(Palette.ink, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("타이머 시작")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 60)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line.opacity(0.6)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .contentShape(.rect)
        .onTapGesture { if r == nil { showStart = true } }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .sheet(isPresented: $showStart) {
            StartTimerSheet(currentPlan: currentPlan, running: running.last) { feedback += 1 }
        }
    }

    private func status(for r: ActualRecord) -> String {
        var s = "\(Fmt.hm(r.start))부터 기록 중"
        if let device = r.deviceName, device != DataStore.deviceName {
            return "\(device)에서 " + s
        }
        if let p = currentPlan, p.categoryID != nil {
            s += p.categoryID == r.detail?.category?.id ? " · 계획과 일치" : " · 계획과 달라요"
        }
        return s
    }
}

/// 타이머 시작 — 지금 하는 일 고르기
struct StartTimerSheet: View {
    let currentPlan: PlanItem?
    let running: ActualRecord?
    let onStarted: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ActivityDetail?
    @State private var askTakeover = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let p = currentPlan, let d = p.detail {
                        Button {
                            start(d)
                        } label: {
                            HStack(spacing: 10) {
                                ColorDot(hex: d.colorHex)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("계획대로 시작").font(.footnote).foregroundStyle(Palette.inkSecondary)
                                    Text(d.fullName).font(.headline)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                            }
                            .foregroundStyle(Palette.ink)
                            .padding(14)
                            .background(Palette.ground, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.pressable)
                    }
                    DetailPicker(selection: $selection)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("기록 시작") {
                    if let s = selection { start(s) }
                }
                .buttonStyle(.primary)
                .disabled(selection == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle("지금 하는 일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .confirmationDialog("\(running?.deviceName ?? "다른 기기")에서 기록 중이에요", isPresented: $askTakeover, titleVisibility: .visible) {
                Button("여기서 이어서 할게요") { if let s = selection { begin(s) } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("타이머는 한 번에 하나만 돌아요. 그쪽 기록은 지금 시각에 끝나요.")
            }
        }
        .appSheet([.large])
    }

    private func start(_ d: ActivityDetail) {
        selection = d
        if let r = running, let device = r.deviceName, device != DataStore.deviceName {
            askTakeover = true
        } else {
            begin(d)
        }
    }

    private func begin(_ d: ActivityDetail) {
        DataStore.startTimer(detail: d, ctx: ctx)
        onStarted()
        dismiss()
    }
}

/// 실제 기록 고치기 · 삭제
struct ActualEditSheet: View {
    @Bindable var record: ActualRecord
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text("기록된 곳").foregroundStyle(Palette.ink)
                            Spacer()
                            if let d = record.detail { ColorDot(hex: d.colorHex) }
                            Text(record.detail?.pathName ?? "미분류").foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    DatePicker("시작", selection: $record.start, displayedComponents: [.date, .hourAndMinute])
                    if record.end != nil {
                        DatePicker("종료", selection: Binding(get: { record.end ?? Date() }, set: { record.end = max($0, record.start) }),
                                   in: record.start..., displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Button("지금 멈추기") { DataStore.stopTimer(record, ctx: ctx); dismiss() }
                    }
                }
                Section("메모") {
                    TextField("메모", text: Binding(get: { record.note ?? "" }, set: { record.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
                Section {
                    LongPressDeleteButton(title: "길게 눌러 기록 삭제") {
                        ctx.delete(record)
                        DataStore.save(ctx)
                        dismiss()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("하루 마감 · 목표 · 인사이트에서도 빠지고 되돌릴 수 없어요.")
                }
            }
            .navigationTitle("실제 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        record.updatedAt = Date()
                        DataStore.save(ctx)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                DetailPickerSheet(title: "기록된 곳", confirmTitle: "바꾸기", initial: record.detail) { d in
                    record.detail = d
                    DataStore.save(ctx)
                }
            }
        }
        .appSheet([.medium, .large])
    }
}
