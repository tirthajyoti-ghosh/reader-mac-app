import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            // Reserve the traffic-light strip (window uses a hidden title bar).
            Color.clear.frame(height: 28)

            // Folder header
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

            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    let recents = model.recentFiles
                    if !recents.isEmpty {
                        SectionLabel(text: "Recent", palette: p)
                        // index-based id: a recent file may also be in the folder list
                        // below, and a duplicate URL id in one LazyVStack blanks a row.
                        ForEach(Array(recents.enumerated()), id: \.offset) { _, url in
                            FileRow(item: fileItem(url), selected: isSelectedURL(url), palette: p)
                                .onTapGesture { model.open(url) }
                        }
                        Rectangle().fill(p.border)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    ForEach(model.sidebarFiles) { item in
                        FileRow(item: item, selected: isSelectedURL(item.url), palette: p)
                            .onTapGesture { model.open(item.url) }
                    }
                }
                .padding(.vertical, 8)
            }

            // Footer
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

    private func fileItem(_ url: URL) -> FileItem {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return FileItem(url: url, modified: m)
    }

    private func isSelectedURL(_ url: URL) -> Bool {
        guard let s = model.selectedDocument?.url else { return false }
        return s.resolvingSymlinksInPath().standardizedFileURL
            == url.resolvingSymlinksInPath().standardizedFileURL
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

private struct FileRow: View {
    let item: FileItem
    let selected: Bool
    let palette: Palette
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.name)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(item.relative)
                .font(.system(size: 12))
                .foregroundColor(palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(selected ? palette.accentSoft : (hover ? palette.bg : Color.clear))
        .overlay(
            Rectangle()
                .fill(selected ? palette.accent : Color.clear)
                .frame(width: 2),
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
