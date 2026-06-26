import Foundation
import Combine

/// A link surface attached to a tab (per-tab, per the spec). External links open
/// as a slide-over sheet that can escalate to a split.
struct LinkSurface: Equatable {
    enum Mode { case sheet, split }
    var url: URL
    var mode: Mode
}

/// One open document = a tab. Reads its file on init and live-reloads via a
/// `FileWatcher` (kqueue). Supports in-place navigation to internal `.md` links
/// with a back stack that restores the prior doc AND its scroll position.
final class Document: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var url: URL
    @Published var title: String
    @Published var text: String

    // In-place internal navigation: pushed (url, scrollTop) we can return to.
    private var backStack: [(url: URL, scrollTop: Double)] = []
    @Published private(set) var breadcrumb: String?   // "Back to <name>" when navigated in
    /// Scroll to restore on the NEXT render after a navigation/back (px from top).
    var restoreScroll: Double = 0

    // Per-tab link surface (external link as sheet/split). nil = none open.
    @Published var surface: LinkSurface?

    // Per-tab document outline (table of contents), pushed from the renderer on
    // every render / live-reload; `activeHeadingID` is the scroll-spied section.
    @Published var headings: [Heading] = []
    @Published var activeHeadingID: String?

    private var watcher: FileWatcher?

    init(url: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.text = Document.read(url)
        rearmWatcher()
    }

    var docDir: String { url.deletingLastPathComponent().path }
    var displayPath: String { Document.displayPath(for: url) }
    var canGoBack: Bool { !backStack.isEmpty }

    // MARK: - In-place navigation

    /// Open an internal `.md` link in this tab, remembering where we were.
    func navigate(to target: URL, currentScroll: Double) {
        backStack.append((url, currentScroll))
        load(target, restoreScroll: 0)
    }

    /// Return to the previous doc and its exact scroll position.
    func goBack() {
        guard let prev = backStack.popLast() else { return }
        load(prev.url, restoreScroll: prev.scrollTop)
    }

    private func load(_ target: URL, restoreScroll: Double) {
        url = target
        title = target.lastPathComponent
        self.restoreScroll = restoreScroll
        breadcrumb = backStack.last?.url.lastPathComponent
        text = Document.read(target)        // republish → re-render
        rearmWatcher()
    }

    // MARK: - IO

    static func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + p.dropFirst(home.count) }
        return p
    }

    static func read(_ url: URL) -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return (try? String(contentsOf: url)) ?? ""
    }

    /// Re-read from disk (live-reload). Scroll is preserved by the WebView host
    /// because the URL is unchanged.
    func reload() {
        let fresh = Document.read(url)
        if fresh != text { text = fresh }
    }

    private func rearmWatcher() {
        watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }
}
