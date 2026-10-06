import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

/// 홈 위젯 S — 오늘 일치율 · 계획/실제 띠 · 다음 계획
struct TodayMatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayMatchWidget", provider: SnapshotProvider()) { entry in
            TodaySmallView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Palette.surface }
                .widgetURL(URL(string: "planactual://today"))
        }
        .configurationDisplayName("오늘 일치")
        .description("오늘 계획과 실제가 얼마나 맞았는지 보여줘요.")
        .supportedFamilies([.systemSmall])
    }
}

/// 잠금화면 원형 위젯 — 일치율 게이지
struct MatchGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MatchGaugeWidget", provider: SnapshotProvider()) { entry in
            Gauge(value: entry.snapshot.matchRate ?? 0) {
                Text("일치")
            } currentValueLabel: {
                Text(entry.snapshot.matchRate.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "planactual://today"))
        }
        .configurationDisplayName("일치율")
        .description("오늘 일치율 게이지")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TodaySmallView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("오늘 일치")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
            Text(snapshot.matchRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                band(snapshot.planBands, plan: true)
                band(snapshot.actualBands, plan: false)
            }
            if let title = snapshot.nextTitle, let start = snapshot.nextStart {
                Text("다음 · \(title) \(start.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            } else {
                Text("남은 계획이 없어요")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func band(_ bands: [WidgetSnapshot.Band], plan: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                    let c = CategoryColors.make(hex: b.colorHex, dark: scheme == .dark)
                    Rectangle()
                        .fill(plan ? c.tint : c.solid)
                        .frame(width: max(1.5, (b.end - b.start) * geo.size.width))
                        .offset(x: b.start * geo.size.width)
                }
                Rectangle().fill(Palette.ink).frame(width: 1.5).offset(x: snapshot.nowFraction * geo.size.width)
            }
            .clipShape(.capsule)
        }
        .frame(height: 8)
    }
}
