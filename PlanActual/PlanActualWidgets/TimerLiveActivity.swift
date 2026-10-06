import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 타이머 라이브 액티비티 — 잠금화면 · 다이내믹 아일랜드 축소/확장
struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLockScreenView(context: context)
                .activityBackgroundTint(Palette.surface.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let color = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(context.attributes.categoryName).font(.caption.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(statusText(context.state)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(intent: StopTimerIntent()) {
                            Image(systemName: "stop.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.18), in: .rect(cornerRadius: 14))
                        .accessibilityLabel("타이머 정지")
                    }
                }
            } compactLeading: {
                Circle().fill(color).frame(width: 10, height: 10)
            } compactTrailing: {
                Text(context.state.startDate, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Circle().fill(color).frame(width: 10, height: 10)
            }
            .widgetURL(URL(string: "planactual://today"))
        }
    }
}

private func statusText(_ s: TimerActivityAttributes.ContentState) -> String {
    guard let title = s.planTitle else { return "계획 없는 시간" }
    return s.matchesPlan ? "계획과 일치 중" : "계획: \(title)"
}

struct TimerLockScreenView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let state = context.state
        HStack(spacing: 12) {
            Circle().fill(Color(hex: context.attributes.colorHex)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let ps = state.planStart, let pe = state.planEnd {
                    HStack(spacing: 4) {
                        Text("계획 \(ps.formatted(date: .omitted, time: .shortened))–\(pe.formatted(date: .omitted, time: .shortened))")
                        if pe > Date() {
                            Text("· 남은")
                            Text(timerInterval: Date()...pe, countsDown: true)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                } else {
                    Text(statusText(state)).font(.caption).foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 4)
            Text(state.startDate, style: .timer)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100, alignment: .trailing)
            Button(intent: StopTimerIntent()) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.ground).frame(width: 12, height: 12)
                    .frame(width: 44, height: 44)
                    .background(Palette.ink, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("타이머 정지")
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
    }
}
