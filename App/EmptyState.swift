import SwiftUI

struct EmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundColor(p.border)
            Text("No document open")
                .font(.system(size: 22, design: .serif))
                .foregroundColor(p.text2)
            HStack(spacing: 5) {
                Text("Select a file from the sidebar, or press")
                Kbd(text: "⌘O", palette: p)
                Text("to open one.")
            }
            .font(.system(size: 13))
            .foregroundColor(p.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
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
