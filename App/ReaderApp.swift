import SwiftUI

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
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
