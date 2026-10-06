import SwiftData
import SwiftUI

/// 17 · 빈 시간 채우기 — 계획, 직전 기록, 건강 앱을 보고 채울 거리를 골라둬요.
struct GapFillView: View {
    let day: Date
    let closesDay: Bool

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(HealthService.self) private var health
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var gaps: [Gap] = []
    @State private var choices: [Int: ActivityDetail] = [:]
    @State private var leaveEmpty: Set<Int> = []
    @State private var pickerFor: Int?
    @State private var loaded = false
    @State private var range: DateInterval?
    @State private var spans: [ActualSpan] = []

    struct Suggestion: Identifiable {
        var id: UUID { detail.id }
        let detail: ActivityDetail
        let label: String
    }

    struct Gap: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let clue: String
        let suggestions: [Suggestion]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Fmt.monthDay(day)).font(.footnote.weight(.medium)).foregroundStyle(Palette.inkSecondary)
                    Text(gaps.isEmpty ? "빈 시간이 없어요" : "기록이 빈 시간이 \(gaps.count)곳 있어요")
                        .font(.title2.bold())
                    Text("계획, 직전 기록, 건강 앱을 보고 채울 거리를 골라뒀어요.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if let range { strip(range) }
                ForEach(gaps) { gap in gapCard(gap) }
            }
            .padding(20)
        }
        .background(Palette.ground)
        .safeAreaInset(edge: .bottom) {
            Button(closesDay ? "채우고 하루 마감하기" : "채우기") { apply() }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(Palette.ground)
        }
        .navigationTitle("빈 시간 채우기")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { pickerFor.map { PickerTarget(id: $0) } }, set: { pickerFor = $0?.id })) { target in
            DetailPickerSheet(title: "무엇을 했나요?", confirmTitle: "이걸로 채우기", initial: choices[target.id]) { d in
                choices[target.id] = d
                leaveEmpty.remove(target.id)
            }
        }
        .task { await load() }
    }

    struct PickerTarget: Identifiable { let id: Int }

    private func strip(_ range: DateInterval) -> some View {
        let total = max(1, range.duration)
        func frac(_ d: Date) -> CGFloat { CGFloat(min(1, max(0, d.timeIntervalSince(range.start) / total))) }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fill)
                    ForEach(spans) { s in
                        BandSegment(hex: s.colorHex, plan: false)
                            .frame(width: max(2, (frac(s.end) - frac(s.start)) * geo.size.width))
                            .offset(x: frac(s.start) * geo.size.width)
                    }
                    ForEach(gaps) { g in
                        Rectangle()
                            .fill(Palette.diverge.opacity(0.35))
                            .overlay(Rectangle().strokeBorder(Palette.diverge, lineWidth: 1))
                            .frame(width: max(3, (frac(g.end) - frac(g.start)) * geo.size.width))
                            .offset(x: frac(g.start) * geo.size.width)
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 16)
            HStack {
                Text(Fmt.hm(range.start))
                Spacer()
                Text(Fmt.hm(range.start.addingTimeInterval(total / 2)))
                Spacer()
                Text(Fmt.hm(range.end))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Palette.inkTertiary)
        }
        .accessibilityHidden(true)
    }

    private func gapCard(_ gap: Gap) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(Fmt.hm(gap.start)) – \(Fmt.hm(gap.end))")
                        .font(.headline)
                        .monospacedDigit()
                    Spacer()
                    Text(gap.clue).font(.caption).foregroundStyle(Palette.inkSecondary)
                }
                FlowLayout(spacing: 8) {
                    ForEach(gap.suggestions) { s in
                        DetailChip(name: s.label, hex: s.detail.colorHex, selected: choices[gap.id]?.id == s.detail.id) {
                            choices[gap.id] = s.detail
                            leaveEmpty.remove(gap.id)
                        }
                    }
                    if let custom = choices[gap.id], !gap.suggestions.contains(where: { $0.detail.id == custom.id }) {
                        DetailChip(name: custom.pathName, hex: custom.colorHex, selected: true) { pickerFor = gap.id }
                    }
                    OutlineChip(title: "다른 것", symbol: "ellipsis") { pickerFor = gap.id }
                    OutlineChip(title: "비워두기", filled: leaveEmpty.contains(gap.id)) {
                        choices[gap.id] = nil
                        leaveEmpty.insert(gap.id)
                    }
                }
            }
        }
    }

    // MARK: 단서 모으기

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let provider = DayDataProvider(ctx: ctx, calendar: calendarService)
        let r = provider.result(for: day)
        range = r.range
        spans = r.spans
        var healthEvents: [HealthEvent] = []
        if prefsList.first?.healthEnabled == true {
            healthEvents = await health.events(in: r.range)
        }
        let found = r.analysis.gaps()
        gaps = found.enumerated().map { index, g in
            let s = r.analysis.date(atMinute: g.lowerBound)
            let e = r.analysis.date(atMinute: g.upperBound + 1)
            return makeGap(id: index, start: s, end: e, result: r, health: healthEvents)
        }
    }

    private func makeGap(id: Int, start: Date, end: Date, result r: DayResult, health events: [HealthEvent]) -> Gap {
        var out: [Suggestion] = []
        var clue = "단서 없음"
        func add(_ d: ActivityDetail?, _ label: String) {
            guard let d, !out.contains(where: { $0.detail.id == d.id }) else { return }
            out.append(Suggestion(detail: d, label: label))
        }
        if let h = events.first(where: { $0.start < end && $0.end > start }) {
            clue = "건강 앱 · \(h.title) \(Fmt.duration(h.minutes))"
            let d = detail(forHealth: h)
            add(d, d?.pathName ?? h.title)
        }
        if let prev = r.spans.last(where: { abs($0.end.timeIntervalSince(start)) < 120 }), let d = prev.detail {
            if clue == "단서 없음" { clue = "직전 기록에서" }
            add(d, "\(d.name) 이어서")
        }
        if let plan = r.items.first(where: { $0.start < end && $0.end > start }), let d = plan.detail {
            if clue == "단서 없음" { clue = "계획에서" }
            add(d, d.pathName)
        }
        if let next = r.spans.first(where: { abs($0.start.timeIntervalSince(end)) < 120 }), let d = next.detail {
            add(d, d.pathName)
        }
        if out.isEmpty, let rest = categories.first(where: { $0.seedKey == "rest" || $0.name == "휴식" })?.activeDetails.last {
            add(rest, rest.pathName)
        }
        return Gap(id: id, start: start, end: end, clue: clue, suggestions: Array(out.prefix(3)))
    }

    private func detail(forHealth h: HealthEvent) -> ActivityDetail? {
        let all = categories.filter { $0.archivedAt == nil }.flatMap(\.activeDetails)
        if let exact = all.first(where: { $0.name == h.title }) { return exact }
        switch h.kind {
        case .sleep:
            return categories.first { $0.seedKey == "sleep" || $0.name == "수면" }?.activeDetails.first
        case .workout:
            let move = categories.first { $0.seedKey == "move" || $0.name == "운동" }
            if h.title == "걷기" { return move?.activeDetails.first { $0.name.contains("산책") } ?? move?.activeDetails.first }
            return move?.activeDetails.first
        }
    }

    private func apply() {
        var created: [ActualRecord] = []
        for gap in gaps {
            guard let d = choices[gap.id] else { continue }
            created.append(DataStore.makeActual(detail: d, start: gap.start, end: gap.end, source: .gapFill, ctx: ctx))
        }
        DataStore.save(ctx)
        if !created.isEmpty {
            toasts.show("빈 시간 \(created.count)곳을 채웠어요", symbol: "square.and.pencil") {
                for r in created { ctx.delete(r) }
                DataStore.save(ctx)
            }
        }
        dismiss()
    }
}
