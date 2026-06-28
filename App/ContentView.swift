import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 0) {
            if model.sidebarVisible {
                Sidebar()
                    .frame(width: model.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                ResizeDivider(palette: p, lineAlignment: .leading,
                              onBegin: { model.beginSidebarResize() },
                              onChange: { model.resizeSidebar(translation: $0) },
                              onEnded: { model.persistPanelWidths() })
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                TopBar()

                HStack(spacing: 0) {
                    ZStack {
                        p.bg
                        // Every open doc keeps its own mounted webview so switching
                        // tabs is instant (no re-render) and scroll is preserved.
                        ForEach(model.documents) { doc in
                            let selected = doc.id == model.selectedID
                            ReadingArea(document: doc, isSelected: selected)
                                .opacity(selected ? 1 : 0)
                                .allowsHitTesting(selected)
                                .zIndex(selected ? 1 : 0)
                        }
                        if model.documents.isEmpty {
                            EmptyState()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    // Right-side outline panel (per-tab; yields to a link split).
                    if let doc = model.selectedDocument {
                        OutlineSlot(document: doc)
                    }
                }
            }
            .background(p.bg)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(p.bg)
        .preferredColorScheme(model.theme.colorScheme)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: model.sidebarVisible)
    }
}

/// A draggable resize handle between a side panel and the reading column. The
/// visible 1px rule sits flush against the panel (`lineAlignment`); the 10px hit
/// area reaches into the reading column (same bg) so there's no seam. Thickens to
/// a clay rule on hover/drag and shows the horizontal-resize cursor. Deltas are
/// reported as cumulative translation so the model can resize from the drag-start
/// width without clamp drift.
struct ResizeDivider: View {
    let palette: Palette
    let lineAlignment: Alignment        // .leading (panel on the left) / .trailing (on the right)
    let onBegin: () -> Void
    let onChange: (CGFloat) -> Void
    var onEnded: () -> Void = {}

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        let active = hovering || dragging
        Color.clear
            .frame(width: 10)
            .overlay(alignment: lineAlignment) {
                Rectangle()
                    .fill(active ? palette.accent : palette.border)
                    .frame(width: active ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if !dragging { dragging = true; onBegin() }
                        onChange(v.translation.width)
                    }
                    .onEnded { _ in dragging = false; onEnded() }
            )
    }
}
