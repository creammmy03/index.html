import SwiftUI

// MARK: 누름 피드백 — 손이 닿는 순간 0.97배

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// 주 버튼: ink 배경 · ground 글자 · 52pt
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.ink
    var foreground: Color = Palette.ground
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(isEnabled ? 1 : 0.35), in: .rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// 보조 버튼: 표면 + 선
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: 색 · 칩

struct ColorDot: View {
    let hex: String
    var size: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(CategoryColors.make(hex: hex, dark: scheme == .dark).solid)
            .frame(width: size, height: size)
    }
}

/// 카테고리 칩 40pt · 모서리 12. 선택 = 틴트 + 1.5pt 테두리
struct CategoryChip: View {
    let name: String
    let hex: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = CategoryColors.make(hex: hex, dark: scheme == .dark)
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(c.solid).frame(width: 10, height: 10)
                Text(name)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? c.planInk : Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(selected ? c.tint : Palette.ground, in: .rect(cornerRadius: 12))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(c.solid, lineWidth: 1.5) }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 세부내역 칩 36pt 캡슐. 선택 = 솔리드
struct DetailChip: View {
    let name: String
    let hex: String
    let selected: Bool
    var symbol: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = CategoryColors.make(hex: hex, dark: scheme == .dark)
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                } else if let symbol {
                    Image(systemName: symbol).font(.caption)
                }
                Text(name).font(.subheadline.weight(selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? c.onSolid : Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(selected ? c.solid : Palette.ground, in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 테두리만 있는 캡슐 (추가 · 필터)
struct OutlineChip: View {
    let title: String
    var symbol: String? = nil
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.footnote.weight(filled ? .semibold : .medium))
            }
            .foregroundStyle(filled ? Palette.ground : Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(filled ? Palette.ink : Palette.surface, in: .capsule)
            .overlay { if !filled { Capsule().strokeBorder(Palette.line) } }
        }
        .buttonStyle(.pressable)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.inkSecondary)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
    }
}

// MARK: 흐름 배치

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: 빗금 (기록 중)

struct HatchPattern: View {
    var color: Color = .white.opacity(0.16)
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 12
            }
            ctx.stroke(path, with: .color(color), lineWidth: 6)
        }
        .allowsHitTesting(false)
    }
}

// MARK: 토스트 + 실행 취소

struct ToastView: View {
    let toast: ToastCenter.Toast
    let onUndo: () -> Void
    let onDismiss: () -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.subheadline.weight(.semibold))
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undo != nil {
                Button("실행 취소", action: onUndo)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 10))
                    .buttonStyle(.pressable)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(Color(hex: "#1C1C1B"), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 15, y: 10)
        .offset(y: max(0, drag))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation.height }
                .onEnded { v in
                    if v.translation.height > 30 || v.predictedEndTranslation.height > 80 { onDismiss() }
                    withAnimation(.spring(duration: 0.35, bounce: 0)) { drag = 0 }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ToastHost: ViewModifier {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let t = toasts.current {
                    ToastView(toast: t, onUndo: { toasts.performUndo() }, onDismiss: { toasts.dismiss() })
                        .id(t.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .animation(.smooth(duration: 0.4), value: toasts.current?.id)
        }
    }
}

extension View {
    func toastHost() -> some View { modifier(ToastHost()) }

    /// 시트 공통: 모서리 28 · 그래버 표시
    func appSheet(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.surface)
    }
}

// MARK: 길게 눌러 삭제 — 1.5초 채움, 놓으면 0.2초에 되돌아감

struct LongPressDeleteButton: View {
    let title: String
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var fired = false

    var body: some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "trash")
            Text(title)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 52)

        ZStack {
            label.foregroundStyle(Palette.destructive)
            label.foregroundStyle(.white)
                .background(Palette.destructive)
                .mask(alignment: .leading) {
                    GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
                }
        }
        .background(Palette.destructive.opacity(0.1), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 30) {
            fired = true
            action()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(.linear(duration: 1.5)) { progress = 1 }
            } else if !fired {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: fired)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("길게 누르면 삭제돼요")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

// MARK: 빈 상태 · 권한 거부

struct PermissionCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(message).font(.footnote).foregroundStyle(Palette.inkSecondary)
                Button(buttonTitle, action: action)
                    .buttonStyle(.secondary)
            }
        }
    }
}
