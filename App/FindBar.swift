import SwiftUI

/// Floating ⌘F find bar, top-right of the reading pane. Drives the native
/// `WKWebView.find(_:configuration:)` (wrap-around) and shows an "n / m" count.
struct FindBar: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        let p = model.palette
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(p.muted)

            TextField("Find in document", text: $model.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(p.text)
                .frame(width: 180)
                .focused($focused)
                .onSubmit { model.runFind(forward: true) }
                .onChange(of: model.findQuery) { _, _ in
                    model.runFind(forward: true, isNewQuery: true)
                }

            if !model.findQuery.isEmpty {
                Text("\(model.findIndex) / \(model.findCount)")
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
        .background(
            RoundedRectangle(cornerRadius: 8).fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? p.accent : p.border, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(p.accentSoft, lineWidth: focused ? 3 : 0)
                .padding(-1.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .padding(.top, 12)
        .padding(.trailing, 24)
        .onAppear { focused = true }
        .onChange(of: model.findFocusToken) { _, _ in focused = true }
        .onExitCommand { model.hideFind() }
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
