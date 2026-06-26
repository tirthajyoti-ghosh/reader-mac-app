import SwiftUI

/// One heading in the document outline. `level` is 0-based (h1 = 0 … h6 = 5);
/// `id` is the heading's anchor slug (unique within a doc — the JS dedupes).
struct Heading: Identifiable, Equatable {
    let id: String
    let text: String
    let level: Int
}

// MARK: - Outline slot (placed right of the reading area)

/// Holds the right-side outline for the front document. Observes the doc so it
/// can yield to a link **split** (which already shares the width with a pane);
/// for a **sheet** it stays put and the sheet simply slides over the doc to its
/// left, so the two never overlap.
struct OutlineSlot: View {
    @ObservedObject var document: Document
    @EnvironmentObject var model: AppModel

    var body: some View {
        let show = model.outlineVisible && document.surface?.mode != .split
        Group {
            if show {
                HStack(spacing: 0) {
                    ResizeDivider(palette: model.palette, lineAlignment: .trailing,
                                  onBegin: { model.beginOutlineResize() },
                                  onChange: { model.resizeOutline(translation: $0) },
                                  onEnded: { model.persistPanelWidths() })
                    OutlinePanel(document: document)
                        .frame(width: model.outlineWidth)
                        .id(document.id)   // fresh filter/scroll state per tab
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: show)
    }
}

// MARK: - Outline panel

/// A quiet table of contents for the front document: every heading nested by
/// level, the active section scroll-spied, a live filter. Native chrome that
/// mirrors the `.outline*` rules in design-tokens.css.
struct OutlinePanel: View {
    @ObservedObject var document: Document
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private let indent: CGFloat = 14   // --outline-indent, added per depth

    private var filtered: [Heading] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return document.headings }
        return document.headings.filter { $0.text.lowercased().contains(q) }
    }

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            header(p)
            if document.headings.isEmpty {
                emptyState(p)
            } else {
                list(p)
            }
        }
        .frame(maxHeight: .infinity)
        .background(p.surface)
    }

    // header: "OUTLINE" label + filter field
    private func header(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundColor(p.muted)
                .padding(.horizontal, 4)         // sp-1
                .padding(.bottom, 6)             // sp-2

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(p.muted)
                TextField("Filter headings", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(p.text)
                    .focused($filterFocused)
                    .disabled(document.headings.isEmpty)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.bg))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(filterFocused ? p.accent : p.border, lineWidth: 1))
            .overlay {                            // soft focus ring (box-shadow 0 0 0 3px)
                if filterFocused {
                    RoundedRectangle(cornerRadius: 8).inset(by: -2)
                        .strokeBorder(p.accentSoft, lineWidth: 3)
                }
            }
        }
        .padding(.horizontal, 9)                 // sp-3
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(p.border.frame(height: 1), alignment: .bottom)
    }

    // the headings list (filtered), auto-scrolled to follow the active section
    private func list(_ p: Palette) -> some View {
        let rows = filtered
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { h in
                        OutlineRow(heading: h, query: filter,
                                   active: h.id == document.activeHeadingID,
                                   indent: indent, palette: p) {
                            model.scrollToHeading(h.id)
                        }
                        .id(h.id)
                    }
                }
                .padding(.horizontal, 6)         // sp-2
                .padding(.top, 6)
                .padding(.bottom, 12)            // sp-4
            }
            .onChange(of: document.activeHeadingID) { _, id in
                guard let id, filter.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // empty state — doc has no headings
    private func emptyState(_ p: Palette) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(p.border)
            Text("No headings")
                .font(.system(size: 13))
                .foregroundColor(p.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
    }
}

// MARK: - One outline row

private struct OutlineRow: View {
    let heading: Heading
    let query: String
    let active: Bool
    let indent: CGFloat
    let palette: Palette
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let p = palette
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: heading.level == 0 ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.trailing, 10)
                .padding(.leading, 6 + CGFloat(heading.level) * indent)   // sp-2 + lvl*14
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(active ? p.accentSoft : (hover ? p.bg : Color.clear)))
                .overlay(alignment: .leading) {
                    if active {
                        RoundedRectangle(cornerRadius: 1).fill(p.accent).frame(width: 2, height: 14)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    // depth tone (deeper = quieter), with the filter match highlighted in clay
    private var label: AttributedString {
        var s = AttributedString(heading.text)
        s.foregroundColor = active ? palette.accent : depthColor
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty, let r = heading.text.range(of: q, options: .caseInsensitive),
           let lo = AttributedString.Index(r.lowerBound, within: s),
           let hi = AttributedString.Index(r.upperBound, within: s) {
            s[lo..<hi].foregroundColor = palette.accent
            s[lo..<hi].backgroundColor = palette.accentSoft
        }
        return s
    }

    private var depthColor: Color {
        switch heading.level {
        case 0:  return palette.text
        case 1:  return palette.text2
        default: return palette.muted
        }
    }
}

// MARK: - Toolbar toggle (sits next to the theme toggle)

struct OutlineToggle: View {
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        let p = model.palette
        let on = model.outlineVisible
        Button { model.toggleOutline() } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundColor(on ? p.accent : (hover ? p.text : p.muted))
                .background(RoundedRectangle(cornerRadius: 7).fill(on || hover ? p.surface : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(on || hover ? p.border : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Outline (⌥⌘O)")
        .onHover { hover = $0 }
    }
}
