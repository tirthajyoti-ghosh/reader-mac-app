import SwiftUI

/// Track S (§8.3.3) image-export dialog — a live card preview on the --code-bg
/// stage, the framing presets (reusing the P0 .segmented / switch vocabulary),
/// and Copy / Save actions. Overlay; mutually exclusive with the settings
/// popover + link sheet. No watermark, no branding.
struct ExportDialog: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Export as image").font(.system(size: 13, weight: .semibold)).foregroundColor(p.text)
                Text(subtitle).font(.system(size: 12)).foregroundColor(p.muted)
                Spacer()
                Button { model.closeExport() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(p.muted).frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
            .overlay(p.border.frame(height: 1), alignment: .bottom)

            // preview stage — the card floats on --code-bg, scaled to fit
            GeometryReader { geo in
                let cardW = max(1, model.exportCardSize.width)
                let cardH = max(1, model.exportCardSize.height)
                let s = min(1, (geo.size.width - 48) / cardW)
                ScrollView(.vertical, showsIndicators: true) {
                    ExportWebView(model: model)
                        .frame(width: cardW, height: cardH)
                        .scaleEffect(s, anchor: .top)
                        .frame(width: cardW * s, height: cardH * s)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                }
            }
            .frame(height: 384)
            .background(p.codeBg)

            // controls row — reused P0 vocabulary
            HStack(spacing: 14) {
                Segmented(options: [("Snug", "snug"), ("Comfortable", "comfortable")],
                          current: model.exportPadding, palette: p) { model.setExportPadding($0) }
                    .fixedSize()
                Segmented(options: [("Social", "social"), ("Docs", "docs")],
                          current: model.exportWidth, palette: p) { model.setExportWidth($0) }
                    .fixedSize()
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(get: { model.exportShadow }, set: { model.setExportShadow($0) }))
                        .labelsHidden().toggleStyle(.switch).tint(p.accent).controlSize(.small)
                    Text("Shadow").font(.system(size: 12)).foregroundColor(p.muted)
                }
                Spacer(minLength: 8)
                Button("Copy") { model.copyExport() }
                    .buttonStyle(ExportButton(primary: false, palette: p))
                Button { model.saveExport() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 11, weight: .semibold))
                        Text("Save…")
                    }
                }
                .buttonStyle(ExportButton(primary: true, palette: p))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(p.border.frame(height: 1), alignment: .top)
        }
        .frame(width: 640)
        .background(p.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(model.colorScheme == .dark ? 0.42 : 0.18), radius: 30, x: 0, y: 18)
        .background(Button("", action: { model.closeExport() }).keyboardShortcut(.cancelAction).opacity(0))
    }

    private var subtitle: String {
        let px = Int(model.exportCardSize.width.rounded()) * AppModel.exportScale
        return "\(model.exportKind == "selection" ? "selection" : "document") · \(px)px"
    }
}

/// The .btn / .btn.primary vocabulary — quiet secondary + clay primary.
struct ExportButton: ButtonStyle {
    let primary: Bool
    let palette: Palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(primary ? palette.bg : palette.text2)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? palette.accent : palette.bg))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(primary ? Color.clear : palette.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
