import SwiftUI

/// A theme's §7.1 color tokens, as hex strings, parsed from `themes.css`.
struct ThemePalette {
    let bg, surface, codeBg, text, textSecondary, textMuted, border, accent, accentEmphasis: String
}

/// One built-in palette from `themes.css` (single source of truth for both the
/// web renderer and the native picker/chrome).
struct BuiltinTheme: Identifiable {
    let id: String        // data-theme value, e.g. "catppuccin-mocha"
    let name: String      // display name, e.g. "Catppuccin"
    let modeLabel: String // e.g. "Mocha" / "Dark" / "Latte"
    let isLight: Bool
    let colors: ThemePalette
}

enum Theming {
    /// Display name + mode label per id (metadata only — colors come from themes.css).
    static let display: [String: (name: String, mode: String)] = [
        "claude-dark": ("Claude", "Dark"), "claude-light": ("Claude", "Light"),
        "catppuccin-mocha": ("Catppuccin", "Mocha"), "catppuccin-latte": ("Catppuccin", "Latte"),
        "dracula": ("Dracula", "Dark"), "nord": ("Nord", "Dark"), "tokyo-night": ("Tokyo Night", "Dark"),
        "rose-pine": ("Rosé Pine", "Dark"), "rose-pine-dawn": ("Rosé Pine", "Dawn"),
        "gruvbox-dark": ("Gruvbox", "Dark"), "gruvbox-light": ("Gruvbox", "Light"),
        "solarized-dark": ("Solarized", "Dark"), "solarized-light": ("Solarized", "Light"),
    ]
    /// Grid display order (Claude flagship first).
    static let order = ["claude-dark", "claude-light", "catppuccin-mocha", "catppuccin-latte",
                        "dracula", "nord", "tokyo-night", "rose-pine", "rose-pine-dawn",
                        "gruvbox-dark", "gruvbox-light", "solarized-dark", "solarized-light"]
    /// Sun/moon toggle flips between a theme's light↔dark pair (dark-only themes fall back).
    static let pairs: [String: String] = [
        "claude-dark": "claude-light", "claude-light": "claude-dark",
        "catppuccin-mocha": "catppuccin-latte", "catppuccin-latte": "catppuccin-mocha",
        "gruvbox-dark": "gruvbox-light", "gruvbox-light": "gruvbox-dark",
        "solarized-dark": "solarized-light", "solarized-light": "solarized-dark",
        "rose-pine": "rose-pine-dawn", "rose-pine-dawn": "rose-pine",
    ]
    /// Curated accent swatches (the no-code Accent tweak → `--accent`).
    static let accents = ["#D97757", "#C6613F", "#268BD2", "#A3BE8C", "#CBA6F7", "#E0AF68"]

    static func loadThemesCSS() -> String {
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("WebResources/themes.css"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    /// Parse the `[data-theme="…"] { … }` blocks from themes.css into the list.
    static func parse(_ css: String) -> [BuiltinTheme] {
        var byId: [String: BuiltinTheme] = [:]
        guard let re = try? NSRegularExpression(pattern: #"\[data-theme="([^"]+)"\]\s*\{([^}]*)\}"#) else { return [] }
        let ns = css as NSString
        re.enumerateMatches(in: css, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            let id = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            func tok(_ name: String) -> String {
                guard let r = body.range(of: "--\(name):") else { return "" }
                return String(body[r.upperBound...].prefix { $0 != ";" }).trimmingCharacters(in: .whitespaces)
            }
            let colors = ThemePalette(
                bg: tok("bg"), surface: tok("surface"), codeBg: tok("code-bg"),
                text: tok("text"), textSecondary: tok("text-secondary"), textMuted: tok("text-muted"),
                border: tok("border"), accent: tok("accent"), accentEmphasis: tok("accent-emphasis"))
            let isLight = body.replacingOccurrences(of: " ", with: "").contains("color-scheme:light")
            let d = display[id] ?? (id, isLight ? "Light" : "Dark")
            byId[id] = BuiltinTheme(id: id, name: d.name, modeLabel: d.mode, isLight: isLight, colors: colors)
        }
        return order.compactMap { byId[$0] } + byId.values.filter { !order.contains($0.id) }
    }
}

extension Color {
    /// Parse `#RRGGBB` (or `RRGGBB`); nil on failure.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension Palette {
    /// Native chrome palette from a parsed theme's §7.1 colors (+ optional accent tweak).
    static func from(_ c: ThemePalette, isLight: Bool, accentHex: String? = nil) -> Palette {
        let accent = accentHex.flatMap { Color(hexString: $0) } ?? Color(hexString: c.accent) ?? Palette.dark.accent
        return Palette(
            bg:         Color(hexString: c.bg) ?? Palette.dark.bg,
            surface:    Color(hexString: c.surface) ?? Palette.dark.surface,
            codeBg:     Color(hexString: c.codeBg) ?? Palette.dark.codeBg,
            text:       Color(hexString: c.text) ?? Palette.dark.text,
            text2:      Color(hexString: c.textSecondary) ?? Palette.dark.text2,
            muted:      Color(hexString: c.textMuted) ?? Palette.dark.muted,
            border:     Color(hexString: c.border) ?? Palette.dark.border,
            accent:     accent,
            accentSoft: accent.opacity(0.14),
            scrim:      Color(.sRGB, white: 0, opacity: isLight ? 0.20 : 0.46)
        )
    }
}
