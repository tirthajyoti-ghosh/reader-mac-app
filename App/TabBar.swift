import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top strip of the reading pane: the tab row plus the theme + outline toggles.
struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 0) {
            // When the sidebar is collapsed the traffic-light cluster floats over
            // this strip — reserve room + a gap so the toggle isn't crammed against it.
            if !model.sidebarVisible {
                Color.clear.frame(width: 72)
            }
            IconButton(system: "sidebar.left", help: "Toggle sidebar") { model.toggleSidebar() }
                .padding(.leading, model.sidebarVisible ? 8 : 12)
                .padding(.trailing, 6)

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
                SettingsToggle()
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
            // Active-tab accent rule on TOP of the tab.
            Rectangle().fill(active ? palette.accent : Color.clear).frame(height: 2),
            alignment: .top
        )
        .overlay(palette.border.frame(width: 1), alignment: .trailing)
        // Middle-click (or a 3-finger trackpad tap mapped to it) closes the tab.
        .overlay(MiddleClickClose { model.closeDocument(doc.id) })
        .opacity(model.draggingTabID == doc.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.select(doc.id) }
        .onHover { hover = $0 }
        // Drag to rearrange tabs.
        .onDrag {
            model.draggingTabID = doc.id
            model.select(doc.id)
            return NSItemProvider(object: doc.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: TabReorderDrop(target: doc, model: model))
    }
}

/// Live-reorders tabs as one is dragged over another (VSCode-style). `dropEntered`
/// fires once per newly-entered tab, so the dragged tab settles into that slot.
private struct TabReorderDrop: DropDelegate {
    let target: Document
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let dragId = model.draggingTabID, dragId != target.id else { return }
        withAnimation(.easeInOut(duration: 0.18)) { model.moveTab(dragId, before: target.id) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { model.draggingTabID = nil; return true }
    func dropExited(info: DropInfo) {}
}

/// Transparent overlay that catches only middle-clicks (button 2) — to close a
/// tab — while letting left/right clicks pass through to the SwiftUI handlers.
private struct MiddleClickClose: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> NSView { MiddleClickView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MiddleClickView)?.action = action
    }
}

private final class MiddleClickView: NSView {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Be hit-test-transparent except while a middle-mouse event is being routed,
    // so left/right clicks reach the SwiftUI tab below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { action() } else { super.otherMouseUp(with: event) }
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
            Image(systemName: model.colorScheme == .dark ? "moon" : "sun.max")
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
