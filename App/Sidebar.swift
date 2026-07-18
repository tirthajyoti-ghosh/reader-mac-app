import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            // Reserve the traffic-light strip (window uses a hidden title bar).
            Color.clear.frame(height: 28)

            // Folder header (unchanged) — folder name + open/pick/refresh actions.
            HStack(spacing: 4) {
                Text(model.sidebarFolderName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(p.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                IconButton(system: "doc.badge.plus", help: "Open file…") { model.openWithPanel() }
                IconButton(system: "folder", help: "Choose folder…") { model.pickFolder() }
                IconButton(system: "arrow.clockwise", help: "Refresh") { model.reloadSidebar() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(p.border.frame(height: 1), alignment: .bottom)

            // The nested file tree (Track F) — filter + Recent + Files hierarchy.
            SidebarTree(tree: model.tree, palette: p)
                .frame(maxHeight: .infinity)

            // Footer (unchanged).
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundColor(p.muted)
                Text("Watching \(model.watchedPathDisplay)")
                    .font(.system(size: 12))
                    .foregroundColor(p.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(p.border.frame(height: 1), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.surface)
    }
}

struct SectionLabel: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundColor(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

struct IconButton: View {
    @EnvironmentObject var model: AppModel
    let system: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let p = model.palette
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundColor(hover ? p.text : p.muted)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? p.bg : Color.clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}
