import SwiftUI
import UIKit

/// 0–255 범위의 sRGB 색. 카테고리 색은 HEX 하나만 저장하고 나머지는 여기서 계산해요.
struct RGB: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF)
        g = Double((v >> 8) & 0xFF)
        b = Double(v & 0xFF)
    }

    static let white = RGB(r: 255, g: 255, b: 255)
    static let black = RGB(r: 0, g: 0, b: 0)
    static let nearBlack = RGB(r: 0x11, g: 0x11, b: 0x10)
    static let darkSurface = RGB(r: 0x1C, g: 0x1C, b: 0x1B)

    var hex: String {
        func c(_ v: Double) -> Int { Int(max(0, min(255, v.rounded()))) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    /// self × keep + other × (1 − keep)
    func mixed(with other: RGB, keep: Double) -> RGB {
        RGB(r: r * keep + other.r * (1 - keep),
            g: g * keep + other.g * (1 - keep),
            b: b * keep + other.b * (1 - keep))
    }

    var luminance: Double {
        func ch(_ v: Double) -> Double {
            let x = v / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }

    func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// 색상각(0–360)과 채도(0–1)
    var hueSaturation: (hue: Double, saturation: Double) {
        let rr = r / 255, gg = g / 255, bb = b / 255
        let mx = max(rr, gg, bb), mn = min(rr, gg, bb), d = mx - mn
        if d == 0 { return (0, 0) }
        var h: Double
        if mx == rr {
            h = ((gg - bb) / d).truncatingRemainder(dividingBy: 6)
        } else if mx == gg {
            h = (bb - rr) / d + 2
        } else {
            h = (rr - gg) / d + 4
        }
        h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        let l = (mx + mn) / 2
        let s = d / (1 - abs(2 * l - 1))
        return (h, s)
    }

    var uiColor: UIColor { UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
    var color: Color { Color(uiColor: uiColor) }
}

extension Color {
    /// "#RRGGBB" 문자열로 색 만들기. 잘못된 값이면 회색.
    init(hex: String) {
        self = (RGB(hex: hex) ?? RGB(r: 0x52, g: 0x60, b: 0x6F)).color
    }
}

enum HexValidator {
    static func normalized(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !s.hasPrefix("#") { s = "#" + s }
        guard RGB(hex: s) != nil else { return nil }
        return s
    }
}

/// 카테고리 HEX 하나에서 계산한 블록 색 묶음 (H4 '사용자 색' 규칙).
struct CategoryColors {
    let solid: Color
    let onSolid: Color
    let tint: Color
    let line: Color
    let planInk: Color
    /// 실제 블록 글자 대비
    let contrast: Double
    let solidRGB: RGB

    static func make(hex: String, dark: Bool) -> CategoryColors {
        let base = RGB(hex: hex) ?? RGB(r: 0x52, g: 0x60, b: 0x6F)
        if dark {
            let solid = base.mixed(with: .white, keep: 0.72)
            let on = bestText(on: solid)
            return CategoryColors(
                solid: solid.color,
                onSolid: on.color,
                tint: base.mixed(with: .darkSurface, keep: 0.24).color,
                line: base.mixed(with: .darkSurface, keep: 0.42).color,
                planInk: base.mixed(with: .white, keep: 0.45).color,
                contrast: solid.contrast(with: on),
                solidRGB: solid
            )
        } else {
            let on = bestText(on: base)
            return CategoryColors(
                solid: base.color,
                onSolid: on.color,
                tint: base.mixed(with: .white, keep: 0.12).color,
                line: base.mixed(with: .white, keep: 0.32).color,
                planInk: base.mixed(with: .black, keep: 0.62).color,
                contrast: base.contrast(with: on),
                solidRGB: base
            )
        }
    }

    /// 흰색과 #111110 중 대비가 높은 쪽
    static func bestText(on bg: RGB) -> RGB {
        bg.contrast(with: .white) >= bg.contrast(with: .nearBlack) ? .white : .nearBlack
    }

    /// 주황·빨강 계열이면 '어긋남'·'삭제' 표시와 헷갈릴 수 있어요.
    static func isWarmWarning(hex: String) -> Bool {
        guard let c = RGB(hex: hex) else { return false }
        let hs = c.hueSaturation
        return hs.saturation > 0.35 && (hs.hue < 40 || hs.hue > 345)
    }
}

struct ColorTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [String]
}

enum ColorThemes {
    static let all: [ColorTheme] = [
        ColorTheme(id: "basic", name: "기본", colors: ["#3B66BE", "#23786F", "#A83E74", "#7048BC", "#52606F", "#9A7B2F", "#2F7D3B", "#0E7490"]),
        ColorTheme(id: "calm", name: "차분", colors: ["#5B6C8F", "#4E7A70", "#8F5E73", "#6F6390", "#5D6670", "#8C7A55", "#5F7A55", "#4F7884"]),
        ColorTheme(id: "vivid", name: "선명", colors: ["#2563EB", "#0F9488", "#DB2777", "#7C3AED", "#475569", "#CA8A04", "#16A34A", "#0891B2"]),
        ColorTheme(id: "pastel", name: "파스텔", colors: ["#8DA9E6", "#7CC4B8", "#E59BBF", "#B7A2E8", "#9FAAB8", "#E3C27A", "#9CCB8F", "#8CC8DA"])
    ]

    static func theme(_ id: String) -> ColorTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static func themeID(containing hex: String) -> String? {
        all.first { $0.colors.contains(hex.uppercased()) }?.id
    }
}
