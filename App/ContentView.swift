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
                        // ONE persistent webview renders the selected doc; switching
                        // tabs re-renders into it (~10ms) instead of mounting a fresh
                        // webview (~190ms first-composite). Scroll is saved per-doc and
                        // restored on switch. Stable identity (no .id) → SwiftUI reuses
                        // the same webview across documents.
                        // Always mounted (placeholder when empty) so the webview
                        // composites at launch → the first open is a fast re-render.
                        ReadingArea(document: model.selectedDocument ?? model.placeholderDoc, isSelected: true)
                        if model.documents.isEmpty {
                            EmptyState()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    // Reading Settings popover (§8.3) — overlays the reading column,
                    // above doc + outline; a link sheet is mutually exclusive (opening
                    // one closes the other). Esc / outside-click close it.
                    .overlay(alignment: .topTrailing) {
                        if model.settingsOpen {
                            ZStack(alignment: .topTrailing) {
                                Color.black.opacity(0.001)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.settingsOpen = false }
                                SettingsPopover()
                                    .padding(.top, 6).padding(.trailing, 10)
                            }
                            .arrowCursor()
                            .transition(.opacity)
                        }
                    }

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
        .preferredColorScheme(model.colorScheme)
        .ignoresSafeArea()
        // Image-export dialog (§8.3.3) — centered modal over everything; the scrim
        // tap + Esc close it. Mutually exclusive with settings + link sheet.
        .overlay {
            if model.exportOpen {
                ZStack {
                    Color.black.opacity(model.colorScheme == .dark ? 0.5 : 0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeExport() }
                    ExportDialog()
                }
                .arrowCursor()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.sidebarVisible)
        .animation(.easeOut(duration: 0.15), value: model.settingsOpen)
        .animation(.easeOut(duration: 0.15), value: model.exportOpen)
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
