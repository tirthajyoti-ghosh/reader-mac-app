import SwiftUI

/// Top strip of the reading pane: the tab row plus the (single) theme toggle.
struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 0) {
            // Reserve the traffic-light strip when the sidebar is collapsed.
            if !model.sidebarVisible {
                Color.clear.frame(width: 70)
            }
            IconButton(system: "sidebar.left", help: "Toggle sidebar") { model.toggleSidebar() }
                .padding(.leading, model.sidebarVisible ? 8 : 0)
                .padding(.trailing, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.documents) { doc in
                        TabItemView(doc: doc, active: doc.id == model.selectedID, palette: p)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ThemeToggle()
                OutlineToggle()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
        .background(p.bg)
        .overlay(p.border.frame(height: 1), alignment: .bottom)
    }
}

private struct TabItemView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var doc: Document
    let active: Bool
    let palette: Palette
    @State private var hover = false
    @State private var closeHover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(doc.title)
                .font(.system(size: 13))
                .foregroundColor(active ? palette.text : palette.muted)
                .lineLimit(1)
            Button {
                model.closeDocument(doc.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .foregroundColor(closeHover ? palette.text : palette.muted)
                    .background(RoundedRectangle(cornerRadius: 4).fill(closeHover ? palette.border : Color.clear))
            }
            .buttonStyle(.plain)
            .opacity(active || hover ? 1 : 0)
            .onHover { closeHover = $0 }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(maxHeight: .infinity)
        .frame(maxWidth: 200)
        .background(active ? palette.surface : Color.clear)
        .overlay(
            Rectangle().fill(active ? palette.accent : Color.clear).frame(height: 2),
            alignment: .bottom
        )
        .overlay(palette.border.frame(width: 1), alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { model.select(doc.id) }
        .onHover { hover = $0 }
    }
}

private struct ThemeToggle: View {
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        let p = model.palette
        Button {
            model.toggleTheme()
        } label: {
            Image(systemName: model.theme == .dark ? "moon" : "sun.max")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundColor(hover ? p.text : p.muted)
                .background(RoundedRectangle(cornerRadius: 7).fill(hover ? p.surface : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(hover ? p.border : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Toggle light / dark")
        .onHover { hover = $0 }
    }
}
