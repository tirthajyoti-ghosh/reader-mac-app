import SwiftUI

struct EmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 18) {
            Image(systemName: "doc.text")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundColor(p.border)

            Text("No document open")
                .font(.system(size: 22, design: .serif))
                .foregroundColor(p.text2)

            VStack(spacing: 8) {
                Button {
                    model.openWithPanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                        Text("Open a file…")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(p.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(p.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack(spacing: 5) {
                    Text("or press")
                    Kbd(text: "⌘O", palette: p)
                }
                .font(.system(size: 12))
                .foregroundColor(p.muted)
            }

            let recents = model.recentFiles
            if !recents.isEmpty {
                VStack(spacing: 1) {
                    SectionLabel(text: "Recently opened", palette: p)
                    ForEach(recents.prefix(6), id: \.self) { url in
                        EmptyRecentRow(url: url, palette: p) { model.open(url) }
                    }
                }
                .frame(width: 340)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
    }
}

private struct EmptyRecentRow: View {
    let url: URL
    let palette: Palette
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? palette.surface : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Kbd: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(palette.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.border, lineWidth: 1))
    }
}
