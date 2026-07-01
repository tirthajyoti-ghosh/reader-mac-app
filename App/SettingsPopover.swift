import SwiftUI
import AppKit

// MARK: - Toolbar "Aa" toggle

struct SettingsToggle: View {
    @EnvironmentObject var model: AppModel
    @State private var hover = false
    var body: some View {
        let p = model.palette
        let on = model.settingsOpen
        Button { model.toggleSettings() } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundColor(on ? p.accent : (hover ? p.text : p.muted))
                .background(RoundedRectangle(cornerRadius: 7).fill(on || hover ? p.surface : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on || hover ? p.border : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Reading settings (⌘,)")
        .onHover { hover = $0 }
    }
}

// MARK: - The Reading Settings popover (P0 container · Theme section = Track T)

struct SettingsPopover: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            // header
            HStack {
                Text("Reading settings").font(.system(size: 13, weight: .semibold)).foregroundColor(p.text)
                Spacer()
                Button { model.settingsOpen = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(p.muted)
                        .frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
            .overlay(p.border.frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ThemeSection()
                    // Reading section — placeholder, owned by the A11y track (§8.3.2)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("READING").font(.system(size: 11, weight: .bold)).tracking(0.9).foregroundColor(p.muted)
                        Text("Accessibility pack fills this later.")
                            .font(.system(size: 12)).foregroundColor(p.muted)
                            .frame(maxWidth: .infinity).padding(16)
                            .background(RoundedRectangle(cornerRadius: 8).fill(p.bg))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(p.border))
                    }
                    .padding(16)
                    .overlay(p.border.frame(height: 1), alignment: .top)
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(p.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(model.colorScheme == .dark ? 0.34 : 0.15), radius: 22, x: 0, y: 16)
        .background(  // Esc closes
            Button("", action: { model.settingsOpen = false }).keyboardShortcut(.cancelAction).opacity(0)
        )
    }
}

// MARK: - Theme section (Track T)

private struct ThemeSection: View {
    @EnvironmentObject var model: AppModel

    private let accents = Theming.accents

    var body: some View {
        let p = model.palette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("THEME").font(.system(size: 11, weight: .bold)).tracking(0.9).foregroundColor(p.muted)
                Spacer()
                if !model.tweaks.isEmpty || model.customCSS != nil {
                    ResetButton("Reset") { model.clearAllTweaks(); model.clearCustomTheme() }
                }
            }

            // 13 built-in theme cards
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(model.builtinThemes) { t in
                    ThemeCard(theme: t, selected: t.id == model.themeId, palette: p) { model.selectTheme(t.id) }
                }
            }

            // ---- no-code tweaks ----
            VStack(alignment: .leading, spacing: 14) {
                // Accent
                VStack(alignment: .leading, spacing: 9) {
                    CtlHead("Accent", token: "--accent")
                    HStack(spacing: 8) {
                        ForEach(accents, id: \.self) { hex in
                            AccentSwatch(hex: hex, selected: model.tweaks["--accent"] == hex, palette: p) {
                                model.setTweak("--accent", hex)
                            }
                        }
                    }
                }
                // Reading face
                CtlRow("Reading face") {
                    Menu {
                        Button("Source Serif 4") { model.clearTweak("--font") }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Source Serif 4").font(.system(size: 13)).foregroundColor(p.text)
                            Image(systemName: "chevron.down").font(.system(size: 10)).foregroundColor(p.muted)
                        }
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.bg))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain).fixedSize()
                }
                // Reading width
                SliderRow(label: "Reading width", token: "--md-max",
                          value: widthBinding, range: 34...60,
                          readout: { $0 >= 60 ? "Full" : "\(Int($0)) rem" }, palette: p)
                // Line height
                SliderRow(label: "Line height", token: "--leading",
                          value: leadingBinding, range: 1.40...2.10,
                          readout: { String(format: "%.2f", $0) }, palette: p)
                // Font size
                CtlRow("Font size", token: "--fs-base") {
                    Stepper28(value: fontSize, range: 13...24, palette: p) { model.setTweak("--fs-base", "\($0)px") }
                }
                // Paragraph spacing
                CtlRow("Paragraph spacing", token: "--para-space") {
                    Segmented(options: [("Tight", "0.7em"), ("Normal", "1.05em"), ("Loose", "1.5em")],
                              current: model.tweaks["--para-space"] ?? "1.05em", palette: p) {
                        model.setTweak("--para-space", $0)
                    }
                }
                // Import custom theme
                ImportRow(palette: p)
            }
        }
        .padding(16)
    }

    // MARK: bindings
    private var widthBinding: Binding<Double> {
        Binding(get: {
            if let v = model.tweaks["--md-max"], let n = Double(v.replacingOccurrences(of: "rem", with: "")) { return n }
            return 60
        }, set: { v in
            if v >= 60 { model.clearTweak("--md-max") } else { model.setTweak("--md-max", "\(Int(v))rem") }
        })
    }
    private var leadingBinding: Binding<Double> {
        Binding(get: { Double(model.tweaks["--leading"] ?? "1.72") ?? 1.72 },
                set: { model.setTweak("--leading", String(format: "%.2f", $0)) })
    }
    private var fontSize: Int { Int((model.tweaks["--fs-base"] ?? "17px").replacingOccurrences(of: "px", with: "")) ?? 17 }
}

// MARK: - Reusable controls (mirror §7.10)

private struct ThemeCard: View {
    let theme: BuiltinTheme
    let selected: Bool
    let palette: Palette
    let action: () -> Void
    private func c(_ h: String) -> Color { Color(hexString: h) ?? .gray }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(c(theme.colors.accent)).frame(width: 11, height: 11)
                    Circle().fill(c(theme.colors.surface))
                        .overlay(Circle().strokeBorder(c(theme.colors.border), lineWidth: 1)).frame(width: 11, height: 11)
                    RoundedRectangle(cornerRadius: 2).fill(c(theme.colors.text).opacity(0.9)).frame(height: 4)
                }
                .padding(.horizontal, 10).frame(height: 40).frame(maxWidth: .infinity, alignment: .leading)
                .background(c(theme.colors.bg))
                .overlay(c(theme.colors.border).frame(height: 1), alignment: .bottom)

                HStack {
                    Text(theme.name).font(.system(size: 12)).foregroundColor(c(theme.colors.text)).lineLimit(1)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            .foregroundColor(c(theme.colors.bg))
                            .frame(width: 14, height: 14).background(Circle().fill(c(theme.colors.accent)))
                    } else {
                        Text(theme.modeLabel.uppercased()).font(.system(size: 9)).tracking(0.5)
                            .foregroundColor(c(theme.colors.text).opacity(0.55))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8).background(c(theme.colors.bg))
            }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(c(theme.colors.surface)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? palette.accent : palette.border, lineWidth: selected ? 2 : 1))
    }
}

private struct AccentSwatch: View {
    let hex: String
    let selected: Bool
    let palette: Palette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(Color(hexString: hex) ?? .gray)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(palette.border, lineWidth: 1))
                .overlay(selected ? Circle().inset(by: -3).strokeBorder(palette.accent, lineWidth: 2) : nil)
        }.buttonStyle(.plain)
    }
}

private struct Segmented: View {
    let options: [(String, String)]   // (label, value)
    let current: String
    let palette: Palette
    let onSelect: (String) -> Void
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { opt in
                let on = opt.1 == current
                Button { onSelect(opt.1) } label: {
                    Text(opt.0).font(.system(size: 12, weight: .medium))
                        .foregroundColor(on ? palette.text : palette.text2)
                        .padding(.vertical, 4).padding(.horizontal, 11).frame(minWidth: 30)
                        .background(RoundedRectangle(cornerRadius: 4).fill(on ? palette.surface : Color.clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 1))
    }
}

private struct Stepper28: View {
    let value: Int
    let range: ClosedRange<Int>
    let palette: Palette
    let onChange: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            btn("minus") { if value > range.lowerBound { onChange(value - 1) } }
            Text("\(value)").font(.system(size: 13)).monospacedDigit().foregroundColor(palette.text)
                .frame(minWidth: 38).frame(height: 28)
                .overlay(palette.border.frame(width: 1), alignment: .leading)
                .overlay(palette.border.frame(width: 1), alignment: .trailing)
            btn("plus") { if value < range.upperBound { onChange(value + 1) } }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func btn(_ sym: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: sym).font(.system(size: 11, weight: .medium)).foregroundColor(palette.text2)
                .frame(width: 26, height: 28)
        }.buttonStyle(.plain)
    }
}

private struct SliderRow: View {
    let label: String
    let token: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: (Double) -> String
    let palette: Palette
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundColor(palette.text)
                if model.tweaks[token] != nil { ResetButton("") { model.clearTweak(token) } }
                Spacer()
                Text(readout(value)).font(.system(size: 12)).monospacedDigit().foregroundColor(palette.muted)
            }
            Slider(value: $value, in: range).tint(palette.accent).controlSize(.small)
        }
    }
}

private struct ImportRow: View {
    @EnvironmentObject var model: AppModel
    let palette: Palette
    @State private var hover = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: importTheme) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                    Text(model.customCSS == nil ? "Import theme…" : "Replace custom theme…").font(.system(size: 13))
                    Spacer()
                    if model.customCSS != nil {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                            .onTapGesture { model.clearCustomTheme(); error = nil }
                    }
                }
                .foregroundColor(hover ? palette.text : palette.text2)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.bg))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundColor(hover ? palette.accent : palette.border))
            }
            .buttonStyle(.plain).onHover { hover = $0 }
            if let error { Text(error).font(.system(size: 11)).foregroundColor(palette.accent) }
        }
    }
    private func importTheme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "css"), .init(filenameExtension: "txt"), .text].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            error = model.importCustomTheme(url)   // nil = success
        }
    }
}

// MARK: label/reset helpers

private struct CtlRow<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let label: String
    var token: String? = nil
    @ViewBuilder let content: Content
    init(_ label: String, token: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label; self.token = token; self.content = content()
    }
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(model.palette.text)
            if let token, model.tweaks[token] != nil { ResetButton("") { model.clearTweak(token) } }
            Spacer()
            content
        }
    }
}

private struct CtlHead: View {
    @EnvironmentObject var model: AppModel
    let label: String
    let token: String
    init(_ label: String, token: String) { self.label = label; self.token = token }
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(model.palette.text)
            Spacer()
            if model.tweaks[token] != nil { ResetButton("Reset") { model.clearTweak(token) } }
        }
    }
}

private struct ResetButton: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .semibold))
                if !title.isEmpty { Text(title).font(.system(size: 12)) }
            }
            .foregroundColor(hover ? model.palette.accent : model.palette.muted)
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}
