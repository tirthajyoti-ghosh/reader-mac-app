import SwiftUI

/// Native chrome colors, mirrored 1:1 from `design-tokens.css` so the SwiftUI
/// shell (sidebar, tabs, find bar, empty state) matches the WKWebView document
/// surface exactly. The web document derives its styling from design-tokens.css
/// directly; this struct is the same palette for the bits AppKit draws.
struct Palette {
    let bg: Color
    let surface: Color
    let codeBg: Color
    let text: Color
    let text2: Color
    let muted: Color
    let border: Color
    let accent: Color
    let accentSoft: Color
    let scrim: Color

    static let dark = Palette(
        bg:         Color(hex: 0x1F1F1E),
        surface:    Color(hex: 0x2C2C2B),
        codeBg:     Color(hex: 0x171716),
        text:       Color(hex: 0xF8F8F6),
        text2:      Color(hex: 0xC3C2B7),
        muted:      Color(hex: 0x97958C),
        border:     Color(hex: 0x454442),
        accent:     Color(hex: 0xD97757),
        accentSoft: Color(hex: 0xD97757, opacity: 0.14),
        scrim:      Color(.sRGB, white: 0, opacity: 0.46)
    )

    static let light = Palette(
        bg:         Color(hex: 0xF8F8F6),
        surface:    Color(hex: 0xFFFFFF),
        codeBg:     Color(hex: 0xEFEEEB),
        text:       Color(hex: 0x121212),
        text2:      Color(hex: 0x373734),
        muted:      Color(hex: 0x7B7974),
        border:     Color(hex: 0xE7E6E1),
        accent:     Color(hex: 0xC6613F),
        accentSoft: Color(hex: 0xC6613F, opacity: 0.10),
        scrim:      Color(.sRGB, white: 0, opacity: 0.20)
    )
}

enum AppTheme: String {
    case dark
    case light

    var palette: Palette { self == .light ? .light : .dark }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Compact "2h", "3d", "now" relative-time label for the sidebar file rows.
func relativeTime(from date: Date, now: Date = Date()) -> String {
    let s = max(0, now.timeIntervalSince(date))
    if s < 60 { return "now" }
    let m = Int(s / 60); if m < 60 { return "\(m)m" }
    let h = m / 60;       if h < 24 { return "\(h)h" }
    let d = h / 24;       if d < 7  { return "\(d)d" }
    let w = d / 7;        if w < 5  { return "\(w)w" }
    let mo = d / 30;      if mo < 12 { return "\(mo)mo" }
    return "\(d / 365)y"
}

/// JSON-encode a Swift string into a JS string literal (including quotes) for
/// safe injection through `evaluateJavaScript`.
func jsStringLiteral(_ s: String) -> String {
    guard let data = try? JSONEncoder().encode(s),
          let str = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return str
}
