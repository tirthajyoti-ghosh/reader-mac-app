import SwiftUI

// MARK: - Tokens (mapped from §7.13 File tree, exactly as chrome mirrors design-tokens.css)

private enum TreeTok {
    static let indent: CGFloat = 14        // --tree-indent (--outline-indent)
    static let padL: CGFloat = 8           // --tree-pad-l (--sp-2)
    static let rowH: CGFloat = 26          // --tree-row-h
    static let lead: CGFloat = 5           // gap between guides/chevron/icon/name
    static let chevron: CGFloat = 14
    static let icon: CGFloat = 15
    static let rowFont: CGFloat = 13       // --ui-size
    static let small: CGFloat = 12         // --ui-small
    static let label: CGFloat = 11         // --ui-label
    static let padR: CGFloat = 16          // --sp-4
    static let guideOpacity: Double = 0.6
}

/// Reports the widest row's natural (content) width so every row can be stretched to
/// it — the selection/hover band then spans the full scrollable width, not just the
/// viewport (the §7.13 "full-content-width highlight" rule).
private struct RowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - The tree (filter + Recent + Files + scrollable hierarchy)

struct SidebarTree: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tree: TreeStore
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            TreeFilterField(text: $tree.filter, palette: palette)
            RecentSection(palette: palette)
            TreeSection(tree: tree, palette: palette)
        }
    }
}

// MARK: - Scrollable hierarchy with full-width bands + keyboard nav

private struct TreeSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tree: TreeStore
    let palette: Palette

    @State private var maxRowWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Files", palette: palette)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tree.rows) { row in
                            TreeRowView(
                                row: row, tree: tree, palette: palette,
                                selectedURL: model.selectedDocument?.url,
                                treeFocused: focused,
                                width: max(viewportWidth, maxRowWidth)
                            )
                            .id(row.id)
                        }
                    }
                    .padding(.vertical, 4)
                    // Pin to (at least) the viewport height, top-aligned — otherwise a
                    // short tree floats to the middle of the 2-axis scroll area.
                    .frame(minHeight: viewportHeight, alignment: .top)
                    .onPreferenceChange(RowWidthKey.self) { maxRowWidth = $0 }
                }
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportWidth = geo.size.width; viewportHeight = geo.size.height }
                        .onChange(of: geo.size.width) { _, w in viewportWidth = w }
                        .onChange(of: geo.size.height) { _, h in viewportHeight = h }
                })
                .onChange(of: tree.scrollTarget?.tick) { _, _ in
                    if let id = tree.scrollTarget?.id {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress { press in handleKey(press) }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:    tree.focusFirstIfNeeded(); tree.moveFocus(-1); return .handled
        case .downArrow:  tree.focusFirstIfNeeded(); tree.moveFocus(1);  return .handled
        case .rightArrow: tree.expandOrDescend(); return .handled
        case .leftArrow:  tree.collapseOrAscend(); return .handled
        case .return:
            if let r = tree.focusedRow {
                if r.kind == .file { model.open(r.url) }
                else if r.kind == .folder { tree.toggle(r.url) }
            }
            return .handled
        default:
            let s = press.characters
            if !s.isEmpty, s.allSatisfy({ !$0.isWhitespace }), press.modifiers.isEmpty {
                tree.typeAhead(s); return .handled
            }
            return .ignored
        }
    }
}

// MARK: - One row (folder / file / empty / no-match)

private struct TreeRowView: View {
    let row: TreeRow
    @ObservedObject var tree: TreeStore
    let palette: Palette
    let selectedURL: URL?
    let treeFocused: Bool
    let width: CGFloat
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        switch row.kind {
        case .empty:   emptyRow
        case .noMatch: noMatchRow
        default:       fileOrFolderRow
        }
    }

    private var isSelected: Bool {
        row.kind == .file && sameFile(row.url, selectedURL)
    }
    private var isFocused: Bool { treeFocused && tree.focusedID == row.id }

    private var fileOrFolderRow: some View {
        let sel = isSelected
        return content
            .background(GeometryReader { g in
                Color.clear.preference(key: RowWidthKey.self, value: g.size.width)
            })
            .frame(width: width, alignment: .leading)              // stretch to content width
            .frame(height: TreeTok.rowH)
            .background(sel ? palette.accentSoft : (hover ? palette.bg : Color.clear))
            .overlay(alignment: .leading) {                        // 2pt accent bar (selected)
                Rectangle().fill(sel ? palette.accent : .clear).frame(width: 2)
            }
            .overlay {                                             // keyboard focus ring
                if isFocused {
                    Rectangle().strokeBorder(palette.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                if row.kind == .folder { tree.toggle(row.url) }
                else { tree.focusedID = row.id; model.open(row.url) }
            }
    }

    // guides + chevron + icon + name, at natural width (measured for the band)
    private var content: some View {
        HStack(spacing: TreeTok.lead) {
            ForEach(0..<row.depth, id: \.self) { _ in
                Rectangle().fill(palette.border).opacity(TreeTok.guideOpacity)
                    .frame(width: 1).frame(width: TreeTok.indent, alignment: .leading)
                    .frame(maxHeight: .infinity)
            }
            // disclosure chevron — folders rotate; files keep an empty slot for alignment
            Group {
                if row.kind == .folder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(palette.muted)
                        .rotationEffect(.degrees(row.isOpen ? 90 : 0))
                } else { Color.clear }
            }
            .frame(width: TreeTok.chevron, height: TreeTok.chevron)

            Image(systemName: row.kind == .folder ? "folder" : "doc")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? palette.accent : palette.muted)
                .frame(width: TreeTok.icon, height: TreeTok.icon)

            name
        }
        .padding(.leading, TreeTok.padL)
        .padding(.trailing, TreeTok.padR)
        .frame(height: TreeTok.rowH)
        .fixedSize(horizontal: true, vertical: false)   // natural width (names never truncate)
    }

    private var name: some View {
        Text(highlighted)
            .font(.system(size: TreeTok.rowFont, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? palette.text : palette.text2)
            .lineLimit(1)
            .fixedSize()
    }

    /// Filter-match highlight (accent-tinted) when filtering.
    private var highlighted: AttributedString {
        var a = AttributedString(row.name)
        let q = tree.filter.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let r = TreeCore.matchRange(name: row.name, query: q),
           let lo = AttributedString.Index(r.lowerBound, within: a),
           let hi = AttributedString.Index(r.upperBound, within: a) {
            a[lo..<hi].foregroundColor = palette.accent
            a[lo..<hi].backgroundColor = palette.accentSoft
        }
        return a
    }

    private var emptyRow: some View {
        Text("empty")
            .font(.system(size: TreeTok.small)).italic()
            .foregroundColor(palette.muted)
            .padding(.leading, TreeTok.padL + CGFloat(row.depth) * TreeTok.indent + 19)
            .frame(height: TreeTok.rowH, alignment: .leading)
            .frame(width: max(width, 1), alignment: .leading)
    }

    private var noMatchRow: some View {
        Text("No files match “\(row.name)”.")
            .font(.system(size: TreeTok.rowFont))
            .foregroundColor(palette.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24).padding(.horizontal, 16)
    }
}

// MARK: - Filter field (reuses the outline-filter vocabulary)

private struct TreeFilterField: View {
    @Binding var text: String
    let palette: Palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11)).foregroundColor(palette.muted)
            TextField("Filter files", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(palette.text)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(palette.muted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? palette.accent : palette.border, lineWidth: 1))
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .overlay(palette.border.frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Section headers + Recent

private struct SectionHeader: View {
    let title: String
    let palette: Palette
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: TreeTok.label, weight: .semibold))
            .tracking(0.9)
            .foregroundColor(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
    }
}

private struct RecentSection: View {
    @EnvironmentObject var model: AppModel
    let palette: Palette
    @State private var collapsed = false

    var body: some View {
        let recents = Array(model.recentFiles.prefix(8))
        if !recents.isEmpty {
            VStack(spacing: 0) {
                Button { collapsed.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold)).foregroundColor(palette.muted)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        Text("RECENT")
                            .font(.system(size: TreeTok.label, weight: .semibold)).tracking(0.9)
                            .foregroundColor(palette.muted)
                        Spacer(minLength: 6)
                        Text("\(recents.count)")
                            .font(.system(size: TreeTok.small)).foregroundColor(palette.muted).opacity(0.7)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !collapsed {
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url, palette: palette,
                                  selected: sameFile(url, model.selectedDocument?.url)) {
                            model.open(url)
                        }
                    }
                }
            }
            .overlay(palette.border.frame(height: 1), alignment: .bottom)
        }
    }
}

private struct RecentRow: View {
    let url: URL
    let palette: Palette
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundColor(palette.muted)
                .frame(width: 14)
            Text(url.lastPathComponent)
                .font(.system(size: TreeTok.rowFont, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? palette.text : palette.text2)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(relativeTime(from: modified))
                .font(.system(size: TreeTok.small)).foregroundColor(palette.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .frame(height: TreeTok.rowH)
        .background(selected ? palette.accentSoft : (hover ? palette.bg : Color.clear))
        .overlay(alignment: .leading) { Rectangle().fill(selected ? palette.accent : .clear).frame(width: 2) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
    private var modified: Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

// MARK: - helpers

func sameFile(_ a: URL?, _ b: URL?) -> Bool {
    guard let a, let b else { return false }
    return a.resolvingSymlinksInPath().standardizedFileURL == b.resolvingSymlinksInPath().standardizedFileURL
}
