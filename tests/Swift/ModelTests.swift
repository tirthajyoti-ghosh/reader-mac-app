import XCTest
import SwiftUI
@testable import ReaderModelTests   // sources compiled into this test module

final class ModelTests: XCTestCase {

    // MARK: Theming.parse — the single source for the picker + chrome palette

    func testParseThemesExtractsColorsAndMode() {
        let css = """
        [data-theme="claude-dark"] {
          --bg:#1F1F1E; --surface:#2C2C2B; --code-bg:#171716;
          --text:#F8F8F6; --text-secondary:#C3C2B7; --text-muted:#97958C; --border:#454442;
          --accent:#D97757; --accent-emphasis:#C6613F;
          color-scheme: dark;
        }
        [data-theme="catppuccin-latte"] {
          --bg:#EFF1F5; --surface:#E6E9EF; --code-bg:#DCE0E8;
          --text:#4C4F69; --text-secondary:#5C5F77; --text-muted:#8C8FA1; --border:#CCD0DA;
          --accent:#1E66F5; --accent-emphasis:#7287FD;
          color-scheme: light;
        }
        """
        let themes = Theming.parse(css)
        XCTAssertEqual(themes.count, 2)
        let dark = themes.first { $0.id == "claude-dark" }
        XCTAssertEqual(dark?.name, "Claude")
        XCTAssertEqual(dark?.isLight, false)
        XCTAssertEqual(dark?.colors.bg, "#1F1F1E")
        XCTAssertEqual(dark?.colors.accent, "#D97757")
        // --accent must not be captured from --accent-emphasis
        XCTAssertEqual(dark?.colors.accentEmphasis, "#C6613F")
        let latte = themes.first { $0.id == "catppuccin-latte" }
        XCTAssertEqual(latte?.isLight, true)
        XCTAssertEqual(latte?.name, "Catppuccin")
    }

    func testThemePairsAreSymmetric() {
        XCTAssertEqual(Theming.pairs["claude-dark"], "claude-light")
        XCTAssertEqual(Theming.pairs["claude-light"], "claude-dark")
        XCTAssertEqual(Theming.pairs["gruvbox-dark"], "gruvbox-light")
        XCTAssertNil(Theming.pairs["dracula"])   // dark-only themes have no pair
    }

    // MARK: Custom-theme import security (§8.5.1)

    func testCustomThemeAcceptsTokenDeclarations() {
        let (css, err) = Theming.validateCustomTheme(":root{--bg:#123456;--accent:#abcdef;}")
        XCTAssertNil(err)
        XCTAssertNotNil(css)
        XCTAssertTrue(css!.contains("--bg: #123456;"))
        XCTAssertTrue(css!.contains("--accent: #abcdef;"))
    }

    func testCustomThemeRejectsImport() {
        let (css, err) = Theming.validateCustomTheme("@import url('http://evil.com/x.css'); --bg:#111;")
        XCTAssertNil(css)
        XCTAssertNotNil(err)
        XCTAssertTrue(err!.contains("@import"))
    }

    func testCustomThemeRejectsRemoteURL() {
        for raw in ["--bg: url(https://evil.com/x.png);", "--x: url(//evil.com/y);"] {
            let (css, err) = Theming.validateCustomTheme(raw)
            XCTAssertNil(css, "should reject: \(raw)")
            XCTAssertNotNil(err)
        }
    }

    func testCustomThemeDropsDataURLTokensButKeepsColors() {
        // data: urls are non-network → the token is dropped, the rest accepted.
        let (css, err) = Theming.validateCustomTheme("--a: url(data:image/png;base64,AAAA); --bg:#222;")
        XCTAssertNil(err)
        XCTAssertNotNil(css)
        XCTAssertTrue(css!.contains("--bg: #222;"))
        XCTAssertFalse(css!.contains("url("))
    }

    func testCustomThemeRejectsFileWithNoTokens() {
        let (css, err) = Theming.validateCustomTheme("body { color: red; }")
        XCTAssertNil(css)
        XCTAssertNotNil(err)
    }

    // MARK: Colour + palette

    func testColorHexStringParsing() {
        XCTAssertNotNil(Color(hexString: "#1F1F1E"))
        XCTAssertNotNil(Color(hexString: "1F1F1E"))
        XCTAssertNil(Color(hexString: "#12"))
        XCTAssertNil(Color(hexString: "nothex"))
    }

    func testPaletteFromUsesAccentOverride() {
        let colors = ThemePalette(bg: "#000000", surface: "#111111", codeBg: "#0A0A0A",
                                  text: "#FFFFFF", textSecondary: "#EEEEEE", textMuted: "#CCCCCC",
                                  border: "#333333", accent: "#D97757", accentEmphasis: "#C6613F")
        let base = Palette.from(colors, isLight: false)
        let overridden = Palette.from(colors, isLight: false, accentHex: "#268BD2")
        XCTAssertEqual(base.accent, Color(hexString: "#D97757"))
        XCTAssertEqual(overridden.accent, Color(hexString: "#268BD2"))
        XCTAssertEqual(base.bg, Color(hexString: "#000000"))
    }

    // MARK: relative-time labels (sidebar)

    func testRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(relativeTime(from: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(relativeTime(from: now.addingTimeInterval(-120), now: now), "2m")
        XCTAssertEqual(relativeTime(from: now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(relativeTime(from: now.addingTimeInterval(-2 * 86400), now: now), "2d")
        XCTAssertEqual(relativeTime(from: now.addingTimeInterval(-14 * 86400), now: now), "2w")
    }

    func testJSStringLiteralEscapes() {
        XCTAssertEqual(jsStringLiteral("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(jsStringLiteral("plain"), "\"plain\"")
    }
}
