import SwiftUI

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // A single `Window` (not `WindowGroup`): opening a file reuses this one
        // window and adds a tab, instead of spawning a new window each time.
        Window("Reader", id: "main") {
            ContentView()
                .environmentObject(model)
                .modifier(WindowOpenerBridge())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Open… replaces "New" — this is a read-only viewer.
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            // No Save — nothing is editable.
            CommandGroup(replacing: .saveItem) { }

            // Find
            CommandGroup(after: .pasteboard) {
                Button("Find…") { model.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") { model.toggleSidebar() }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Toggle Outline") { model.toggleOutline() }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Button("Reading Settings") { model.toggleSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Toggle Light / Dark") { model.toggleTheme() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Refresh Sidebar") { model.reloadSidebar() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Close Tab") { model.closeSelected() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(model.selectedID == nil)
            }
        }
    }
}

/// Bridges SwiftUI's `openWindow` action out to AppKit. A single `Window`
/// scene's window can be *closed* (red button) while the app keeps running;
/// once closed there's no NSWindow to raise, so AppDelegate can't bring it back
/// on a file-open — only `openWindow(id:)` can recreate it. We capture that
/// action here (it stays valid for the app's lifetime) and stash it where the
/// AppDelegate can call it.
private struct WindowOpenerBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            WindowOpener.shared.reopen = { openWindow(id: "main") }
        }
    }
}

/// Holds the captured `openWindow` action so non-SwiftUI code (AppDelegate) can
/// reopen the main window.
final class WindowOpener {
    static let shared = WindowOpener()
    var reopen: (() -> Void)?
}
