import SwiftUI

/// 하루 범위 ↔ 세로 좌표
struct TimelineMetrics {
    let range: DateInterval
    /// 1시간 높이 — 52pt(일) · 36pt(주) · 30pt(시간표)
    let hourHeight: CGFloat
    var topInset: CGFloat = 8

    var totalHeight: CGFloat { CGFloat(range.duration / 3600) * hourHeight + topInset * 2 }

    func y(_ date: Date) -> CGFloat {
        topInset + CGFloat(date.timeIntervalSince(range.start) / 3600) * hourHeight
    }

    func y(minute: Int) -> CGFloat {
        topInset + CGFloat(minute) / 60 * hourHeight
    }

    func height(_ start: Date, _ end: Date) -> CGFloat {
        max(0, y(end) - y(start))
    }

    func date(atY y: CGFloat, snap: Int = 15) -> Date {
        let minutes = Double((y - topInset) / hourHeight * 60)
        let raw = range.start.addingTimeInterval(minutes * 60)
        let clamped = min(max(raw, range.start), range.end)
        return clamped.snapped(toMinutes: snap)
    }

    /// 정각 눈금
    var hourMarks: [(y: CGFloat, label: String)] {
        let cal = DayClock.calendar
        var marks: [(y: CGFloat, label: String)] = []
        var d = cal.dateInterval(of: .hour, for: range.start)?.start ?? range.start
        if d < range.start { d = d.addingTimeInterval(3600) }
        while d <= range.end {
            let h = cal.component(.hour, from: d)
            marks.append((y: y(d), label: String(format: "%02d", h)))
            d = d.addingTimeInterval(3600)
        }
        return marks
    }
}

/// 시간축 숫자와 가로선
struct HourGrid: View {
    let metrics: TimelineMetrics
    var labelWidth: CGFloat = 44
    var trailing: CGFloat = 16
    var showsLabels = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(metrics.hourMarks.enumerated()), id: \.offset) { _, mark in
                HStack(spacing: 8) {
                    if showsLabels {
                        Text(mark.label)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: labelWidth, alignment: .trailing)
                    }
                    Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1)
                }
                .padding(.trailing, trailing)
                .frame(height: 12)
                .offset(y: mark.y - 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 트랙 블록 — 계획 = 틴트 + 1pt 선, 실제 = 솔리드. 44pt 미만이면 제목만.
struct TrackBlockView: View {
    enum Style { case plan, actual }

    let style: Style
    let title: String
    var subtitle: String? = nil
    let hex: String
    let height: CGFloat
    var symbols: [String] = []
    var pending = false
    var running = false
    var dimmed = false
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = CategoryColors.make(hex: hex, dark: scheme == .dark)
        let tall = height >= 44
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: compact ? 10.5 : 12.5, weight: .semibold))
                    .lineLimit(compact ? 3 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(symbols, id: \.self) { s in
                    Image(systemName: s).font(.system(size: compact ? 8 : 10, weight: .bold))
                }
            }
            if tall, let subtitle, !compact {
                Text(subtitle)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .opacity(0.85)
                    .lineLimit(1)
            }
            if pending && height >= 60 && !compact {
                Spacer(minLength: 0)
                Text("확인 필요")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.divergeInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Palette.diverge.opacity(0.35)))
            }
        }
        .foregroundStyle(style == .plan ? c.planInk : c.onSolid)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, tall ? 6 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 6 : 10)
                .fill(style == .plan ? c.tint : c.solid)
                .overlay {
                    if running { HatchPattern().clipShape(.rect(cornerRadius: compact ? 6 : 10)) }
                }
                .overlay {
                    if style == .plan {
                        RoundedRectangle(cornerRadius: compact ? 6 : 10).strokeBorder(pending ? Palette.diverge.opacity(0.6) : c.line, lineWidth: 1)
                    }
                }
        }
        .frame(height: max(4, height))
        .opacity(dimmed ? 0.5 : 1)
        .clipped()
    }
}

/// 현재 시각 선 — 1.5pt 선 + 시각 캡슐
struct NowLine: View {
    let now: Date
    var labelWidth: CGFloat = 48
    var showsLabel = true

    var body: some View {
        HStack(spacing: 4) {
            if showsLabel {
                Text(Fmt.hm(now))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ground)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Palette.ink, in: .rect(cornerRadius: 6))
                    .frame(width: labelWidth, alignment: .trailing)
            }
            Rectangle().fill(Palette.ink).frame(height: 1.5)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// 싱크 솔기 — 일치 ink · 어긋남 diverge · 미래 점선
struct SeamView: View {
    let segments: [SeamSegment]
    let metrics: TimelineMetrics
    let nowY: CGFloat
    let endY: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let x = size.width / 2
            for s in segments {
                let y0 = metrics.y(minute: s.startMinute) + 1
                let y1 = metrics.y(minute: s.endMinute) - 1
                guard y1 > y0 else { continue }
                let rect = CGRect(x: x - 1.5, y: y0, width: 3, height: y1 - y0)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(s.matched ? Palette.ink : Palette.diverge))
            }
            if endY > nowY {
                var p = Path()
                p.move(to: CGPoint(x: x, y: nowY))
                p.addLine(to: CGPoint(x: x, y: endY))
                ctx.stroke(p, with: .color(Palette.inkTertiary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
