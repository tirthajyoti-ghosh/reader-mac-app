import AppKit

/// Receives file-open events (double-click in Finder, `open` from the shell,
/// the system default-handler path) and routes them to the shared AppModel.
/// Also makes sure the single window is actually surfaced — when the app is
/// backgrounded / minimized / on another Space, a file-open should bring the
/// window forward, not just flip the menu bar to "Reader" with nothing on screen.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// True when the app is launched by the test/measurement harness (via the
    /// READER_TESTING env var, or an XCTest host). In this mode we never call
    /// `NSApp.activate(ignoringOtherApps:)` / `orderFrontRegardless()` — so a build
    /// under test can't yank focus away from whatever the user is doing elsewhere.
    static let isTestingRun: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["READER_TESTING"] == "1" || env["XCTestConfigurationFilePath"] != nil
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure the window is shown on launch. A cold launch triggered by a
        // file-open can deliver the open event before the `Window` scene has
        // built its window, so relying only on `application(_:open:)` can leave
        // the window created-but-unraised. Surfacing here (with retry) closes that.
        surfaceWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.open(urls)
        surfaceWindow()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        AppModel.shared.open(URL(fileURLWithPath: filename))
        surfaceWindow()
        return true
    }

    /// Dock-click / reopen with no visible window → bring the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        surfaceWindow()
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Make sure the single window is visible and frontmost. Covers every state
    /// the window can be in when a file-open / reopen / launch arrives:
    ///   • closed (red button, app still running) → recreate it via `openWindow`;
    ///   • minimized / on another Space / behind → un-minimize + raise;
    ///   • not created yet (cold launch — the open event can beat the `Window`
    ///     scene's window creation) → retry until it exists, then raise.
    private func surfaceWindow(attempt: Int = 0) {
        let testing = Self.isTestingRun
        if !testing { NSApp.activate(ignoringOtherApps: true) }
        // Recreate the window if it was closed. No-op (just brings it forward)
        // when it already exists, since this is a single `Window` scene.
        WindowOpener.shared.reopen?()

        if let win = NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.collectionBehavior.insert(.moveToActiveSpace)
            if win.isMiniaturized { win.deminiaturize(nil) }
            if testing {
                // Show the window (so the webview isn't occluded → no render throttling
                // that would skew measurements) but do NOT make it key / steal focus.
                win.orderFront(nil)
            } else {
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()   // show even if the app isn't yet active
            }
        } else if attempt < 30 {
            // Window not up yet (cold launch). Poll until it appears (~4.5s cap).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.surfaceWindow(attempt: attempt + 1)
            }
        }
    }
}
