import EventKit
import SwiftData
import SwiftUI

enum GoalsRoute: Hashable {
    case todos
}

/// 기간 안의 실제 · 앞으로 계획된 분 (카테고리 · 세부내역별)
struct PeriodStats {
    var actualByCategory: [UUID: Int] = [:]
    var actualByDetail: [UUID: Int] = [:]
    var plannedByCategory: [UUID: Int] = [:]
    var plannedByDetail: [UUID: Int] = [:]

    func actual(for goal: Goal) -> Int {
        if let d = goal.detail { return actualByDetail[d.id] ?? 0 }
        if let c = goal.category { return actualByCategory[c.id] ?? 0 }
        return 0
    }

    func planned(for goal: Goal) -> Int {
        if let d = goal.detail { return plannedByDetail[d.id] ?? 0 }
        if let c = goal.category { return plannedByCategory[c.id] ?? 0 }
        return 0
    }

    static func interval(for period: GoalPeriod, now: Date) -> DateInterval {
        let cal = DayClock.calendar
        switch period {
        case .week:
            let s = DayClock.weekStart(for: now)
            return DateInterval(start: s, end: DayClock.addDays(7, to: s))
        case .month:
            return cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 86400 * 30)
        case .year:
            return cal.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 86400 * 365)
        }
    }

    @MainActor
    static func compute(period: GoalPeriod, provider: DayDataProvider, now: Date = Date()) -> PeriodStats {
        var stats = PeriodStats()
        let span = interval(for: period, now: now)
        let includeArchived = provider.prefs.includeArchivedInStats
        for r in DataStore.actuals(in: span, ctx: provider.ctx) {
            if !includeArchived && (r.detail?.isArchived ?? false) { continue }
            let s = max(r.start, span.start), e = min(r.end ?? now, span.end, now)
            guard e > s, let d = r.detail else { continue }
            let m = Int(e.timeIntervalSince(s) / 60)
            stats.actualByDetail[d.id, default: 0] += m
            if let c = d.category { stats.actualByCategory[c.id, default: 0] += m }
        }
        let today = provider.clock.logicalDay(for: now)
        var days: [Date] = []
        var d = today
        while d < span.end {
            days.append(d)
            d = DayClock.addDays(1, to: d)
        }
        for result in provider.results(for: days, now: now) {
            for item in result.items {
                let s = max(item.start, now), e = item.end
                guard e > s, let detail = item.detail else { continue }
                let m = Int(e.timeIntervalSince(s) / 60)
                stats.plannedByDetail[detail.id, default: 0] += m
                if let c = detail.category { stats.plannedByCategory[c.id, default: 0] += m }
            }
        }
        return stats
    }
}

/// 탭 3 · 목표와 할 일 (05)
struct GoalsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query private var allActuals: [ActualRecord]
    @State private var period: GoalPeriod = .week
    @State private var editing: Goal?
    @State private var creating = false
    @State private var path: [GoalsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("기간", selection: $period) {
                        ForEach(GoalPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    content
                    TodoSummaryCard { path.append(.todos) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.ground)
            .navigationTitle("목표")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("목표 추가")
                }
            }
            .navigationDestination(for: GoalsRoute.self) { _ in TodosView() }
            .sheet(item: $editing) { g in GoalEditSheet(goal: g, defaultPeriod: period) }
            .sheet(isPresented: $creating) { GoalEditSheet(goal: nil, defaultPeriod: period) }
            .toastHost()
        }
    }

    @ViewBuilder
    private var content: some View {
        let _ = allActuals.count
        let now = Date()
        let interval = PeriodStats.interval(for: period, now: now)
        let stats = PeriodStats.compute(period: period, provider: DayDataProvider(ctx: ctx, calendar: calendarService), now: now)
        let remaining = max(0, DayClock.calendar.dateComponents([.day], from: DayClock.calendar.startOfDay(for: now), to: interval.end).day ?? 0)
        let list = goals.filter { $0.period == period }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(periodLabel(interval)) · \(remaining)일 남음")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                HStack(spacing: 10) {
                    legend("실제", Palette.ink)
                    legend("계획됨", Palette.ink.opacity(0.3))
                }
            }
            if list.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(period.label) 목표가 없어요").font(.headline)
                        Text("카테고리나 세부내역에 시간 목표를 정하면, 실제 기록과 앞으로의 계획으로 채워질지 알려줘요.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Button("목표 만들기") { creating = true }.buttonStyle(.secondary)
                    }
                }
            }
            ForEach(list) { g in
                Button { editing = g } label: {
                    GoalCard(goal: g, actual: stats.actual(for: g), planned: stats.planned(for: g))
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 6)
            Text(text).font(.caption2).foregroundStyle(Palette.inkSecondary)
        }
    }

    private func periodLabel(_ i: DateInterval) -> String {
        switch period {
        case .week: return "\(Fmt.monthDay(i.start)) – \(Fmt.dayNumber(i.end.addingTimeInterval(-1)))일"
        case .month: return "\(DayClock.calendar.component(.month, from: i.start))월"
        case .year: return "\(DayClock.calendar.component(.year, from: i.start))년"
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    let actual: Int
    let planned: Int
    @Environment(\.colorScheme) private var scheme

    private var hint: (String, Bool) {
        let target = goal.targetMinutes
        if actual >= target { return ("목표를 채웠어요", false) }
        let shortfall = target - actual - planned
        if shortfall <= 0 { return ("계획대로 하면 목표를 채워요 · \(Fmt.clock(planned)) 계획됨", false) }
        if shortfall <= 60 { return ("\(Fmt.clock(planned)) 계획됨 · \(Fmt.duration(shortfall))만 더 잡으면 돼요", true) }
        return ("계획된 시간만으로는 \(Fmt.duration(shortfall))이 부족해요", true)
    }

    var body: some View {
        let c = CategoryColors.make(hex: goal.colorHex, dark: scheme == .dark)
        let target = max(1, goal.targetMinutes)
        let actualFrac = min(1, CGFloat(actual) / CGFloat(target))
        let plannedFrac = min(1, CGFloat(actual + planned) / CGFloat(target))
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ColorDot(hex: goal.colorHex)
                    Text(goal.displayName).font(.headline)
                    if goal.detail != nil, let cat = goal.detail?.category?.name {
                        Text(cat).font(.caption).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                    Text("\(Fmt.clock(actual)) / \(Fmt.clock(goal.targetMinutes))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Palette.ink)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fill)
                        Capsule().fill(c.tint).overlay(Capsule().strokeBorder(c.line)).frame(width: geo.size.width * plannedFrac)
                        Capsule().fill(c.solid).frame(width: geo.size.width * actualFrac)
                    }
                }
                .frame(height: 10)
                Text(hint.0)
                    .font(.footnote)
                    .foregroundStyle(hint.1 ? Palette.divergeInk : Palette.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GoalEditSheet: View {
    let goal: Goal?
    let defaultPeriod: GoalPeriod
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @State private var byDetail = false
    @State private var category: ActivityCategory?
    @State private var detail: ActivityDetail?
    @State private var period: GoalPeriod = .week
    @State private var hours: Double = 10
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("대상", selection: $byDetail) {
                        Text("카테고리 전체").tag(false)
                        Text("세부내역").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if byDetail {
                        DetailPicker(selection: $detail)
                            .padding(.vertical, 6)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories.filter { $0.archivedAt == nil }) { c in
                                    CategoryChip(name: c.name, hex: c.colorHex, selected: category?.id == c.id) { category = c }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                Section {
                    Picker("기간", selection: $period) {
                        ForEach(GoalPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper(value: $hours, in: 0.5...500, step: period == .week ? 0.5 : (period == .month ? 1 : 5)) {
                        HStack {
                            Text("목표 시간")
                            Spacer()
                            Text(Fmt.duration(Int(hours * 60))).monospacedDigit().foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                if let goal {
                    Section {
                        Button("목표 지우기", role: .destructive) {
                            ctx.delete(goal)
                            DataStore.save(ctx)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(goal == nil ? "새 목표" : "목표")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(byDetail ? detail == nil : category == nil)
                }
            }
            .onAppear(perform: load)
        }
        .appSheet([.large])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        period = goal?.period ?? defaultPeriod
        if let goal {
            byDetail = goal.detail != nil
            detail = goal.detail
            category = goal.category ?? goal.detail?.category
            hours = Double(goal.targetMinutes) / 60
        } else {
            category = categories.first { $0.archivedAt == nil }
            hours = defaultPeriod == .week ? 10 : (defaultPeriod == .month ? 40 : 400)
        }
    }

    private func save() {
        let g: Goal
        if let goal {
            g = goal
        } else {
            g = Goal(period: period, targetMinutes: Int(hours * 60))
            ctx.insert(g)
        }
        g.period = period
        g.targetMinutes = Int(hours * 60)
        if byDetail {
            g.detail = detail
            g.category = nil
        } else {
            g.category = category
            g.detail = nil
        }
        g.updatedAt = Date()
        DataStore.save(ctx)
        dismiss()
    }
}
