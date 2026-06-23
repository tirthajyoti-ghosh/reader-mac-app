import SwiftUI
import AppKit

/// Floating ⌘F find bar, top-right of the reading pane. Drives the renderer's JS
/// find engine (highlights all matches, cycles the current one) and shows "n / m".
struct FindBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(p.muted)

            FindTextField(
                text: $model.findQuery,
                focusToken: model.findFocusToken,
                textColor: NSColor(p.text),
                placeholderColor: NSColor(p.muted),
                onChange: { model.findQueryChanged() },
                onEnter: { model.runFind(forward: true) },
                onShiftEnter: { model.runFind(forward: false) },
                onEscape: { model.hideFind() }
            )
            .frame(width: 190, height: 18)

            if !model.findQuery.isEmpty {
                Text(findCountLabel)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundColor(p.muted)
            }

            FindIcon(system: "chevron.up", palette: p) { model.runFind(forward: false) }
            FindIcon(system: "chevron.down", palette: p) { model.runFind(forward: true) }
            FindIcon(system: "xmark", palette: p) { model.hideFind() }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.accent, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.accentSoft, lineWidth: 3).padding(-1.5))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .padding(.top, 12)
        .padding(.trailing, 24)
    }

    /// Before navigating: just the match count. While cycling: "i / N".
    private var findCountLabel: String {
        if model.findCount == 0 { return "0/0" }
        if model.findIndex == 0 { return "\(model.findCount)" }
        return "\(model.findIndex) / \(model.findCount)"
    }
}

/// AppKit-backed text field so we get reliable focus + select-all when the bar
/// opens, and proper Enter / Shift-Enter / Esc handling.
private struct FindTextField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var textColor: NSColor
    var placeholderColor: NSColor
    var onChange: () -> Void
    var onEnter: () -> Void
    var onShiftEnter: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: 13)
        tf.textColor = textColor
        tf.cell?.usesSingleLineMode = true
        tf.cell?.isScrollable = true
        tf.lineBreakMode = .byTruncatingTail
        tf.stringValue = text
        tf.placeholderAttributedString = placeholder()
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        if tf.stringValue != text { tf.stringValue = text }
        tf.textColor = textColor
        tf.placeholderAttributedString = placeholder()
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                // selectText makes the field first responder AND selects all text,
                // so typing immediately replaces any existing query.
                tf.selectText(nil)
            }
        }
    }

    private func placeholder() -> NSAttributedString {
        NSAttributedString(string: "Find in document",
                           attributes: [.foregroundColor: placeholderColor,
                                        .font: NSFont.systemFont(ofSize: 13)])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindTextField
        var lastFocusToken = Int.min
        init(_ p: FindTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
            parent.onChange()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { parent.onShiftEnter() }
                else { parent.onEnter() }
                return true
            case #selector(NSResponder.cancelOperation(_:)):   // Esc
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

private struct FindIcon: View {
    let system: String
    let palette: Palette
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundColor(hover ? palette.text : palette.muted)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? palette.border : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
