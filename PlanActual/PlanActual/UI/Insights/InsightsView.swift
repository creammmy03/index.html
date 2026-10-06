import Charts
import SwiftData
import SwiftUI

enum InsightRange: String, CaseIterable, Identifiable {
    case week = "이번 주"
    case month = "최근 4주"
    var id: String { rawValue }
}

/// 주간 어긋남 분석
struct InsightReport {
    struct Cell: Identifiable {
        var id: String { "\(row)-\(col)" }
        let row: Int      // 0 = 월
        let col: Int      // 0 = 06–08시
        let minutes: Int
        var level = 0
        var dayLabel: String { ["월", "화", "수", "목", "금", "토", "일"][row] }
        var hourLabel: String { String(format: "%02d", 6 + col * 2) }
    }

    var cells: [Cell] = []
    var averageMatch: Double?
    var headline: String?
    var detailLine: String?
    var categoryLines: [String] = []
    var suggestion: (category: ActivityCategory, detail: ActivityDetail?, hour: Int, rate: Double)?
    var dayCount = 0

    static func hourText(_ h: Int) -> String {
        let h24 = ((h % 24) + 24) % 24
        let ampm = h24 < 12 ? "오전" : "오후"
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return "\(ampm) \(h12)"
    }

    @MainActor
    static func build(results: [DayResult], categories: [ActivityCategory]) -> InsightReport {
        var report = InsightReport()
        var grid = Array(repeating: Array(repeating: 0, count: 9), count: 7)
        var bucketUnion = Array(repeating: 0, count: 9), bucketMatch = Array(repeating: 0, count: 9)
        var cellDays = Array(repeating: Array(repeating: Set<String>(), count: 9), count: 7)
        var takeovers: [String: Int] = [:]
        var planPerCat: [UUID: Int] = [:], actualPerCat: [UUID: Int] = [:], daysPerCat: [UUID: Int] = [:]
        var delays: [UUID: [Int]] = [:]
        var rates: [Double] = []
        var bucketCatMinutes: [UUID: [Int]] = [:]
        let catByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for r in results {
            let a = r.analysis
            guard a.elapsedMinutes > 0 else { continue }
            if let rate = a.matchRate { rates.append(rate) }
            let row = (DayClock.weekday(r.day) + 5) % 7
            let key = DayClock.dayKey(r.day)
            var dayPlan: [UUID: Int] = [:], dayActual: [UUID: Int] = [:]
            var firstPlan: [UUID: Int] = [:], firstActual: [UUID: Int] = [:]
            for i in 0..<a.elapsedMinutes {
                let p = a.plan[i], q = a.actual[i]
                if let p, p != DayAnalysis.uncategorized {
                    dayPlan[p, default: 0] += 1
                    if firstPlan[p] == nil { firstPlan[p] = i }
                }
                if let q, q != DayAnalysis.uncategorized {
                    dayActual[q, default: 0] += 1
                    if firstActual[q] == nil { firstActual[q] = i }
                }
                guard p != nil || q != nil else { continue }
                let hour = ((r.clock.startMinute + i) / 60) % 24
                guard hour >= 6 else { continue }
                let col = min(8, (hour - 6) / 2)
                bucketUnion[col] += row < 5 ? 1 : 0
                if p != nil && p == q {
                    bucketMatch[col] += row < 5 ? 1 : 0
                } else {
                    grid[row][col] += 1
                    cellDays[row][col].insert(key)
                    if let p, let q { takeovers["\(q.uuidString)>\(p.uuidString)", default: 0] += 1 }
                }
                if let p, p != DayAnalysis.uncategorized, p == q, row < 5 {
                    var arr = bucketCatMinutes[p] ?? Array(repeating: 0, count: 9)
                    arr[col] += 1
                    bucketCatMinutes[p] = arr
                }
            }
            for (c, m) in dayPlan {
                planPerCat[c, default: 0] += m
                actualPerCat[c, default: 0] += dayActual[c] ?? 0
                daysPerCat[c, default: 0] += 1
                if let fp = firstPlan[c], let fa = firstActual[c] { delays[c, default: []].append(fa - fp) }
            }
        }

        report.dayCount = rates.count
        report.averageMatch = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        let maxV = grid.flatMap { $0 }.max() ?? 0
        for row in 0..<7 {
            for col in 0..<9 {
                let v = grid[row][col]
                let level = v == 0 || maxV == 0 ? 0 : max(1, Int(ceil(Double(v) / Double(maxV) * 4)))
                report.cells.append(Cell(row: row, col: col, minutes: v, level: level))
            }
        }

        if maxV > 0, let top = report.cells.max(by: { $0.minutes < $1.minutes }) {
            let weekday = top.row < 5
            let group = weekday ? "평일" : "주말"
            let start = 6 + top.col * 2
            report.headline = "\(group) \(hourText(start))–\(hourText(start + 2).split(separator: " ").last ?? "")시에 가장 자주 어긋나요"
            let groupRows = weekday ? Array(0..<5) : [5, 6]
            let groupDays = results.filter { groupRows.contains((DayClock.weekday($0.day) + 5) % 7) && $0.analysis.elapsedMinutes > 0 }.count
            let hitDays = Set(groupRows.flatMap { cellDays[$0][top.col] }).count
            var line = "\(group) \(groupDays)일 중 \(hitDays)일"
            if let best = takeovers.max(by: { $0.value < $1.value }) {
                let ids = best.key.split(separator: ">").compactMap { UUID(uuidString: String($0)) }
                if ids.count == 2, let took = catByID[ids[0]], let lost = catByID[ids[1]] {
                    line += " · 대부분 \(took.name)이 \(lost.name) 시간을 차지했어요"
                }
            }
            report.detailLine = line
        }

        for (c, days) in daysPerCat where days >= 2 {
            guard let cat = catByID[c] else { continue }
            let avg = (actualPerCat[c, default: 0] - planPerCat[c, default: 0]) / days
            if abs(avg) >= 10 {
                report.categoryLines.append("\(cat.name)은 계획보다 평균 \(Fmt.duration(abs(avg))) \(avg < 0 ? "짧아요" : "길어요")")
            }
            if let ds = delays[c], ds.count >= 2 {
                let d = ds.reduce(0, +) / ds.count
                if abs(d) >= 10 {
                    report.categoryLines.append("\(cat.name)은 계획보다 평균 \(Fmt.duration(abs(d))) \(d > 0 ? "늦게" : "일찍") 시작해요")
                }
            }
        }

        // 제안: 평일 중 일치율이 가장 높은 2시간 칸으로 가장 많이 짧아지는 카테고리를 옮겨보기
        var bestCol: Int?
        var bestRate = 0.0
        for col in 0..<9 where bucketUnion[col] >= 60 {
            let rate = Double(bucketMatch[col]) / Double(bucketUnion[col])
            if rate > bestRate { bestRate = rate; bestCol = col }
        }
        let shortfalls = daysPerCat.compactMap { c, days -> (UUID, Int)? in
            let gap = planPerCat[c, default: 0] - actualPerCat[c, default: 0]
            return days >= 2 && gap > 0 ? (c, gap / days) : nil
        }
        if let col = bestCol, let worst = shortfalls.max(by: { $0.1 < $1.1 }), worst.1 >= 15, let cat = catByID[worst.0] {
            report.suggestion = (cat, cat.activeDetails.first, 6 + col * 2, bestRate)
        }
        return report
    }
}

/// 탭 4 · 어긋남 인사이트 (16)
struct InsightsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CalendarService.self) private var calendarService
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var summaries: [DaySummary]
    @State private var range: InsightRange = .week
    @AppStorage("insightDismissedWeek") private var dismissedWeek = ""

    private let scale = ["#F0F0ED", "#FBE3D2", "#F5B98F", "#E57A35", "#B23F0A"]
    private let darkScale = ["#262624", "#4A2A18", "#7A3E1C", "#B5571F", "#F07A3F"]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                let _ = summaries.count
                let report = makeReport()
                VStack(alignment: .leading, spacing: 18) {
                    Picker("범위", selection: $range) {
                        ForEach(InsightRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("언제 어긋나나요").font(.headline)
                                Spacer()
                                Text("평균 일치 \(Fmt.percent(report.averageMatch))")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                            }
                            heatmap(report)
                            HStack(spacing: 6) {
                                Text("적게").font(.caption2).foregroundStyle(Palette.inkSecondary)
                                ForEach(0..<5, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3).fill(color(level: i)).frame(width: 14, height: 10)
                                }
                                Text("자주 어긋남").font(.caption2).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }

                    if let h = report.headline {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(h).font(.title3.bold())
                            if let d = report.detailLine {
                                Text(d).font(.footnote).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    } else {
                        Text(report.dayCount == 0 ? "아직 비교할 기록이 없어요. 계획을 세우고 실제를 기록하면 언제 어긋나는지 보여줘요." : "이 기간에는 크게 어긋난 시간이 없어요.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }

                    if !report.categoryLines.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(report.categoryLines, id: \.self) { line in
                                HStack(spacing: 10) {
                                    Circle().fill(Palette.diverge).frame(width: 6, height: 6)
                                    Text(line).font(.subheadline)
                                }
                                .padding(.vertical, 10)
                                if line != report.categoryLines.last { Divider() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
                    }

                    if let s = report.suggestion, dismissedWeek != weekKey {
                        suggestionCard(s)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.ground)
            .navigationTitle("인사이트")
            .toastHost()
        }
    }

    private var weekKey: String { DayClock.dayKey(DayClock.weekStart(for: Date())) }

    private func makeReport() -> InsightReport {
        let provider = DayDataProvider(ctx: ctx, calendar: calendarService)
        let today = provider.clock.logicalDay(for: Date())
        let days: [Date]
        switch range {
        case .week:
            let start = DayClock.weekStart(for: today)
            days = (0..<7).map { DayClock.addDays($0, to: start) }.filter { $0 <= today }
        case .month:
            days = (0..<28).map { DayClock.addDays(-$0, to: today) }.reversed()
        }
        return InsightReport.build(results: provider.results(for: days), categories: categories)
    }

    private func color(level: Int) -> Color {
        Color(hex: (scheme == .dark ? darkScale : scale)[max(0, min(4, level))])
    }

    private func heatmap(_ report: InsightReport) -> some View {
        Chart(report.cells) { c in
            RectangleMark(
                x: .value("시간", c.hourLabel),
                y: .value("요일", c.dayLabel),
                width: .ratio(0.9),
                height: .ratio(0.86)
            )
            .foregroundStyle(color(level: c.level))
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel() }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in AxisValueLabel() }
        }
        .chartLegend(.hidden)
        .frame(height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.headline ?? "요일과 시간대별 어긋남 히트맵")
    }

    private func suggestionCard(_ s: (category: ActivityCategory, detail: ActivityDetail?, hour: Int, rate: Double)) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("제안").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
                Text("\(s.category.name)을 \(InsightReport.hourText(s.hour))시로 옮겨볼까요?").font(.headline)
                Text("\(InsightReport.hourText(s.hour))–\(InsightReport.hourText(s.hour + 2).split(separator: " ").last ?? "")시는 일치율이 \(Fmt.percent(s.rate))로 가장 높아요")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                HStack(spacing: 8) {
                    Button("다음 주 템플릿에 반영") { applySuggestion(s) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("괜찮아요") { dismissedWeek = weekKey }
                        .buttonStyle(.secondary)
                        .frame(maxWidth: 120)
                }
            }
        }
    }

    /// 활성 시간표에서 그 카테고리의 평일 칸을 제안 시각으로 옮겨요 (없으면 평일 1시간 칸 추가).
    private func applySuggestion(_ s: (category: ActivityCategory, detail: ActivityDetail?, hour: Int, rate: Double)) {
        let nextWeek = DayClock.addDays(7, to: DayClock.weekStart(for: Date()))
        let tt = PlanResolver.activeTimetable(for: nextWeek, in: timetables) ?? {
            let t = Timetable(name: "기본 시간표", isActive: true, sortOrder: timetables.count)
            ctx.insert(t)
            return t
        }()
        let targets = (tt.slots ?? []).filter { $0.detail?.category?.id == s.category.id && (2...6).contains($0.weekday) }
        var undo: [() -> Void] = []
        if targets.isEmpty, let d = s.detail {
            for wd in 2...6 {
                let slot = DataStore.makeSlot(in: tt, detail: d, weekday: wd, startMinute: s.hour * 60, endMinute: s.hour * 60 + 60, place: nil, ctx: ctx)
                undo.append { ctx.delete(slot) }
            }
        } else {
            for slot in targets {
                let old = (slot.startMinute, slot.endMinute)
                let dur = slot.durationMinutes
                slot.startMinute = s.hour * 60
                slot.endMinute = s.hour * 60 + dur
                slot.updatedAt = Date()
                undo.append { slot.startMinute = old.0; slot.endMinute = old.1 }
            }
        }
        DataStore.save(ctx)
        dismissedWeek = weekKey
        toasts.show("‘\(tt.name)’에 반영했어요", symbol: "tablecells") {
            for u in undo { u() }
            DataStore.save(ctx)
        }
    }
}
