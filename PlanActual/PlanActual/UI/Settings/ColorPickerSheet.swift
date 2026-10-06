import SwiftData
import SwiftUI
import UIKit

/// 19 · 카테고리 색 · 테마 · HEX (category가 nil이면 색 테마 고르기)
struct ColorPickerSheet: View {
    let category: ActivityCategory?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]

    @State private var hex = "#3B66BE"
    @State private var hexText = "#3B66BE"
    @State private var themeID = "basic"
    @State private var loaded = false

    private var customColors: [String] { prefsList.first?.customColors ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if category != nil {
                        HStack(spacing: 12) {
                            preview(dark: false)
                            preview(dark: true)
                        }
                        contrastLine
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(text: "테마").padding(.bottom, 8)
                        ForEach(ColorThemes.all) { t in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(t.name).font(.subheadline.weight(t.id == themeID ? .semibold : .regular))
                                    if t.id == themeID { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                                }
                                HStack(spacing: 0) {
                                    ForEach(t.colors, id: \.self) { c in
                                        swatch(c) {
                                            themeID = t.id
                                            hex = c
                                            hexText = c
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            if t.id != ColorThemes.all.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Palette.surface, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))

                    if category != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "직접 입력 · HEX")
                            HStack(spacing: 8) {
                                TextField("#RRGGBB", text: $hexText)
                                    .font(.body.monospaced())
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 12)
                                    .frame(height: 44)
                                    .background(Palette.surface, in: .rect(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HexValidator.normalized(hexText) == nil ? Palette.diverge : Palette.line))
                                    .onChange(of: hexText) { _, v in
                                        if let n = HexValidator.normalized(v) { hex = n }
                                    }
                                ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { c in
                                    let n = RGB.from(color: c).hex
                                    hex = n
                                    hexText = n
                                }), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 44, height: 44)
                                Button("추가") { addCustom() }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .background(Palette.ink, in: .rect(cornerRadius: 12))
                                    .foregroundStyle(Palette.ground)
                                    .disabled(HexValidator.normalized(hexText) == nil)
                            }
                            if !customColors.isEmpty {
                                SectionLabel(text: "내가 추가한 색")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(customColors, id: \.self) { c in
                                            VStack(spacing: 2) {
                                                swatch(c) { hex = c; hexText = c }
                                                Text(c).font(.system(size: 9).monospaced()).foregroundStyle(Palette.inkSecondary)
                                            }
                                            .contextMenu {
                                                Button(role: .destructive) { removeCustom(c) } label: { Label("지우기", systemImage: "trash") }
                                            }
                                        }
                                    }
                                }
                            }
                            if CategoryColors.isWarmWarning(hex: hex) {
                                Label("주황·빨강 계열은 ‘어긋남’·‘삭제’ 표시와 헷갈릴 수 있어요.", systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.divergeInk)
                            }
                        }
                    }

                    Button("‘\(ColorThemes.theme(themeID).name)’ 테마를 모든 카테고리에 적용") { applyThemeToAll() }
                        .buttonStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle(category.map { "‘\($0.name)’ 색" } ?? "색 테마")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("완료") { save() } }
            }
        }
        .appSheet([.large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let prefs = prefsList.first
            if let c = category {
                hex = c.colorHex.uppercased()
                hexText = hex
                themeID = c.themeID ?? ColorThemes.themeID(containing: hex) ?? prefs?.activeThemeID ?? "basic"
            } else {
                themeID = prefs?.activeThemeID ?? "basic"
            }
        }
    }

    private func swatch(_ c: String, action: @escaping () -> Void) -> some View {
        let selected = category != nil && c.uppercased() == hex.uppercased()
        return Button(action: action) {
            Circle()
                .fill(Color(hex: c))
                .frame(width: 28, height: 28)
                .overlay {
                    if selected {
                        Circle().strokeBorder(Palette.surface, lineWidth: 2)
                            .background(Circle().strokeBorder(Palette.ink, lineWidth: 1.5).padding(-3.5))
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(c)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func preview(dark: Bool) -> some View {
        let c = CategoryColors.make(hex: hex, dark: dark)
        return VStack(alignment: .leading, spacing: 8) {
            Text(dark ? "다크" : "라이트").font(.caption.weight(.semibold))
                .foregroundStyle(dark ? Color(hex: "#A3A39E") : Color(hex: "#5E5E5A"))
            Text("계획 · 기획서")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(c.planInk)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .background(c.tint, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.line))
            Text("실제 · 기획서")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(c.onSolid)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .background(c.solid, in: .rect(cornerRadius: 10))
        }
        .padding(12)
        .background(dark ? Color(hex: "#111110") : Color(hex: "#F7F7F5"), in: .rect(cornerRadius: 16))
        .environment(\.colorScheme, dark ? .dark : .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dark ? "다크" : "라이트") 미리보기")
    }

    private var contrastLine: some View {
        let ratio = CategoryColors.make(hex: hex, dark: false).contrast
        return HStack(spacing: 8) {
            Text(String(format: "실제 블록 글자 대비 %.1f : 1", ratio)).monospacedDigit()
            Spacer()
            Text(ratio >= 4.5 ? "읽기 좋아요" : "글자색 자동 조정")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ratio >= 4.5 ? Palette.ground : Palette.divergeTint, in: .capsule)
                .foregroundStyle(ratio >= 4.5 ? Palette.ink : Palette.divergeInk)
        }
        .font(.footnote)
    }

    private func addCustom() {
        guard let n = HexValidator.normalized(hexText) else { return }
        let p = DataStore.preferences(ctx)
        if !p.customColors.contains(n) {
            p.customColors = Array((p.customColors + [n]).suffix(16))
            p.updatedAt = Date()
            DataStore.save(ctx)
        }
        hex = n
    }

    private func removeCustom(_ c: String) {
        let p = DataStore.preferences(ctx)
        p.customColors.removeAll { $0 == c }
        DataStore.save(ctx)
    }

    private func applyThemeToAll() {
        let theme = ColorThemes.theme(themeID)
        let sorted = categories.sorted { $0.sortOrder < $1.sortOrder }
        let previous = sorted.map { ($0, $0.colorHex, $0.themeID) }
        for (i, c) in sorted.enumerated() {
            c.colorHex = theme.colors[i % theme.colors.count]
            c.themeID = theme.id
            c.updatedAt = Date()
        }
        let p = DataStore.preferences(ctx)
        p.activeThemeID = theme.id
        DataStore.save(ctx)
        if let category { hex = category.colorHex; hexText = hex }
        toasts.show("모든 카테고리에 ‘\(theme.name)’ 테마를 적용했어요", symbol: "paintpalette") {
            for (c, h, t) in previous { c.colorHex = h; c.themeID = t }
            DataStore.save(ctx)
        }
    }

    private func save() {
        if let c = category {
            c.colorHex = hex
            c.themeID = ColorThemes.themeID(containing: hex)
            c.updatedAt = Date()
        } else {
            let p = DataStore.preferences(ctx)
            p.activeThemeID = themeID
            p.updatedAt = Date()
        }
        DataStore.save(ctx)
        dismiss()
    }
}

extension RGB {
    static func from(color: Color) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: Double(max(0, min(1, r))) * 255, g: Double(max(0, min(1, g))) * 255, b: Double(max(0, min(1, b))) * 255)
    }
}
