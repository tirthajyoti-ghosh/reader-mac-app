import SwiftUI
import AppKit

/// macOS cursor conventions (Apple HIG):
///   • Arrow — the default for all non-text controls: buttons, toggles, segmented
///     controls, sliders, menus, tabs, sidebar rows, toolbar icons, labels.
///     Native macOS does NOT use the pointing hand for buttons (that's a web idiom).
///   • I-beam — editable fields AND selectable static text (the reading webview
///     correctly shows this so you can select the document).
///   • Pointing hand — hyperlinks only (WebKit already applies it to `.md a`).
///   • Resize — pane dividers (ResizeDivider already pushes `.resizeLeftRight`).
///
/// The bug this fixes: our overlays (settings popover, export dialog) float above
/// the selectable doc webview, whose I-beam tracking leaks onto the overlay's
/// chrome. `arrowCursor()` reasserts the arrow while hovering the overlay, using
/// the same push/pop pattern as the resize dividers.
extension View {
    func arrowCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.arrow.push() } else { NSCursor.pop() }
        }
    }
}
