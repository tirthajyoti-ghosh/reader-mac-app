import AppKit

/// Receives file-open events (double-click in Finder, `open` from the shell,
/// the system default-handler path) and routes them to the shared AppModel.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.open(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        AppModel.shared.open(URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
