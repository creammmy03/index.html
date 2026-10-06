import SwiftData
import SwiftUI

enum CloseRoute: Hashable {
    case gaps
}

/// 04 하루 마감 — 전체 화면. 빈 시간이 있으면 17을 먼저 보여줘요.
struct DayCloseFlow: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @State private var path: [CloseRoute] = []
    @State private var checked = false

    var body: some View {
        NavigationStack(path: $path) {
            SummaryView(day: day, onFinish: { dismiss() }, onFillGaps: { path.append(.gaps) })
                .navigationDestination(for: CloseRoute.self) { _ in
                    GapFillView(day: day, closesDay: true)
                }
        }
        .onAppear {
            guard !checked else { return }
            checked = true
            let provider = DayDataProvider(ctx: ctx, calendar: calendarService)
            let result = provider.result(for: day)
            let closed = DataStore.summary(dayKey: DayClock.dayKey(day), ctx: ctx)?.closedAt != nil
            if !closed && !result.analysis.gaps().isEmpty {
                path = [.gaps]
            }
        }
    }
}

/// 04 · 하루 마감
struct SummaryView: View {
    let day: Date
    let onFinish: () -> Void
    let onFillGaps: () -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @Environment(HealthService.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [ActualRecord]
    @Query private var blocks: [PlanBlock]
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    @State private var note = ""
    @State private var reveal: CGFloat = 0
    @State private var healthEvents: [HealthEvent] = []
    @State private var done = false
    @State private var loaded = false
    @FocusState private var noteFocused: Bool

    init(day: Date, onFinish: @escaping () -> Void, onFillGaps: @escaping () -> Void) {
        self.day = day
        self.onFinish = onFinish
        self.onFillGaps = onFillGaps
        let r = DayClock.standard.range(for: day)
        let s = r.start.addingTimeInterval(-86400), e = r.end.addingTimeInterval(86400)
        _records = Query(filter: #Predicate<ActualRecord> { $0.start < e && $0.start > s })
        _blocks = Query(filter: #Predicate<PlanBlock> { $0.start < e && $0.end > s })
    }

    private var provider: DayDataProvider { DayDataProvider(ctx: ctx, calendar: calendarService) }

    var body: some View {
        let _ = (records.count, blocks.count)
        let result = provider.result(for: day)
        let rate = result.analysis.matchRate
        let previous = DataStore.summary(dayKey: DayClock.dayKey(DayClock.addDays(-1, to: day)), ctx: ctx)?.matchRate
        let totals = result.analysis.totals(categories: categories)
        let gaps = result.analysis.gaps()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Fmt.dayTitle(day)) · 계획과 일치")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(Fmt.percent(rate))
                        .font(.system(size: 64, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.identity)
                    if let rate, let previous {
                        let diff = Int(((rate - previous) * 100).rounded())
                        Text(diff == 0 ? "\(Fmt.weekdayLong(DayClock.addDays(-1, to: day)))과 같아요"
                             : "\(Fmt.weekdayLong(DayClock.addDays(-1, to: day)))보다 \(abs(diff))%p \(diff > 0 ? "높아요" : "낮아요")")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                bands(result)

                if !gaps.isEmpty {
                    Button(action: onFillGaps) {
                        HStack(spacing: 10) {
                            Circle().fill(Palette.diverge).frame(width: 8, height: 8)
                            Text("기록이 빈 시간이 \(gaps.count)곳 있어요").font(.footnote.weight(.medium))
                            Spacer()
                            Text("채우기").font(.footnote.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Palette.divergeInk)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Palette.divergeTint, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.pressable)
                }

                table(totals)

                if !healthEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(healthSummary, id: \.self) { line in
                            Label(line, systemImage: "heart.text.square")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("오늘의 메모").font(.headline)
                    TextField("어떤 하루였나요? 내일은 무엇을 바꿀까요?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .focused($noteFocused)
                        .padding(12)
                        .background(Palette.surface, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground)
        .safeAreaInset(edge: .bottom) {
            Button(done ? "마감했어요" : "하루 마감하기") {
                DataStore.closeDay(day: day, clock: result.clock, items: result.items, matchRate: rate, note: note, ctx: ctx)
                done = true
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    onFinish()
                }
            }
            .buttonStyle(.primary)
            .disabled(done)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(Palette.ground)
        }
        .sensoryFeedback(.success, trigger: done)
        .navigationTitle("하루 마감")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { onFinish() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("닫기")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { noteFocused = false }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            note = DataStore.summary(dayKey: DayClock.dayKey(day), ctx: ctx)?.note ?? ""
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.6)) { reveal = 1 }
        }
        .task {
            guard prefsList.first?.healthEnabled == true else { return }
            healthEvents = await health.events(in: provider.result(for: day).range.union(with: DayClock.calendar.dateInterval(of: .day, for: day)))
        }
    }

    private var healthSummary: [String] {
        var lines: [String] = []
        let sleep = healthEvents.filter { $0.kind == .sleep }.reduce(0) { $0 + $1.minutes }
        if sleep > 0 { lines.append("건강 · 수면 \(Fmt.duration(sleep))") }
        var workouts: [String: Int] = [:]
        for w in healthEvents where w.kind == .workout { workouts[w.title, default: 0] += w.minutes }
        for (k, v) in workouts.sorted(by: { $0.value > $1.value }) { lines.append("건강 · \(k) \(Fmt.duration(v))") }
        return lines
    }

    // 계획 / 실제 띠 — 좌→우로 드러남
    private func bands(_ r: DayResult) -> some View {
        let total = max(1, r.range.duration)
        func frac(_ d: Date) -> CGFloat { CGFloat(min(1, max(0, d.timeIntervalSince(r.range.start) / total))) }
        let hours = stride(from: 0, through: Int(total / 3600), by: 4).map { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 10) {
                    Text(row == 0 ? "계획" : "실제")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 30, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.fill)
                            if row == 0 {
                                ForEach(r.items) { i in
                                    BandSegment(hex: i.colorHex, plan: true)
                                        .frame(width: max(2, (frac(i.end) - frac(i.start)) * geo.size.width))
                                        .offset(x: frac(i.start) * geo.size.width)
                                }
                            } else {
                                ForEach(r.spans) { s in
                                    BandSegment(hex: s.colorHex, plan: false)
                                        .frame(width: max(2, (frac(s.end) - frac(s.start)) * geo.size.width))
                                        .offset(x: frac(s.start) * geo.size.width)
                                }
                            }
                        }
                        .clipShape(.capsule)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geo.size.width * reveal)
                        }
                    }
                    .frame(height: 18)
                }
            }
            HStack(spacing: 10) {
                Color.clear.frame(width: 30, height: 1)
                GeometryReader { geo in
                    ForEach(hours, id: \.self) { h in
                        Text(Fmt.hm(r.range.start.addingTimeInterval(Double(h) * 3600)).prefix(2))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                            .offset(x: geo.size.width * CGFloat(Double(h) * 3600 / total) - 6)
                    }
                }
                .frame(height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("계획과 실제 띠, 일치 \(Fmt.percent(r.analysis.matchRate))")
    }

    private func table(_ totals: [CategoryTotal]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text("활동")
                Text("계획").gridColumnAlignment(.trailing)
                Text("실제").gridColumnAlignment(.trailing)
                Text("차이").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.inkSecondary)
            .padding(.bottom, 8)
            ForEach(totals) { t in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    HStack(spacing: 8) {
                        ColorDot(hex: t.colorHex)
                        Text(t.name).font(.subheadline.weight(.medium))
                    }
                    Text(Fmt.clock(t.planMinutes))
                    Text(Fmt.clock(t.actualMinutes))
                    Text(Fmt.signedClock(t.diff))
                        .foregroundStyle(t.diff < -10 ? Palette.divergeInk : Palette.ink)
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.vertical, 10)
            }
            if totals.isEmpty {
                GridRow {
                    Text("아직 계획도 기록도 없어요")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .gridCellColumns(4)
                }
            }
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
    }
}

struct BandSegment: View {
    let hex: String
    let plan: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = CategoryColors.make(hex: hex, dark: scheme == .dark)
        Rectangle().fill(plan ? c.tint : c.solid)
            .overlay { if plan { Rectangle().strokeBorder(c.line, lineWidth: 1) } }
    }
}

extension DateInterval {
    func union(with other: DateInterval?) -> DateInterval {
        guard let other else { return self }
        return DateInterval(start: min(start, other.start), end: max(end, other.end))
    }
}
