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
    /// True while the file is being read off the main thread. Drives a subtle
    /// loading veil so a slow (cold) read never freezes the UI or flashes blank.
    @Published private(set) var isLoading: Bool = false

    /// Bumped on every (re)load; a completing read whose token is stale is dropped,
    /// so a newer open/navigation can't be clobbered by an older in-flight read.
    private var loadToken = 0

    // In-place internal navigation: pushed (url, scrollTop) we can return to.
    private var backStack: [(url: URL, scrollTop: Double)] = []
    @Published private(set) var breadcrumb: String?   // "Back to <name>" when navigated in
    /// Scroll to restore on the NEXT render after a navigation/back (px from top).
    var restoreScroll: Double = 0
    /// Last known scroll position — saved continuously so switching tabs (one
    /// shared webview) restores this doc exactly where it was.
    var savedScroll: Double = 0

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
        self.text = ""
        Perf.event("open.init", url.lastPathComponent)
        // Read off the main thread — the tab appears instantly and the read (which
        // can block for seconds on a cold/TCC-gated file) never freezes the UI.
        loadTextAsync(url, showLoading: true)
        rearmWatcher()
    }

    /// A blank, watcher-less placeholder — keeps the single reading webview mounted
    /// (and its compositor warm) before any real document is opened, so the first
    /// open is a fast re-render instead of a cold webview mount.
    init() {
        self.url = URL(fileURLWithPath: "/")
        self.title = ""
        self.text = ""
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
        url = target                        // update identity synchronously (drives render/urlChanged)
        title = target.lastPathComponent
        self.restoreScroll = restoreScroll
        breadcrumb = backStack.last?.url.lastPathComponent
        loadTextAsync(target, showLoading: true)   // text republishes when the read returns
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

    /// Read `target` on a background queue and publish `text` back on the main
    /// thread. The main thread never blocks on file I/O. A per-load token drops the
    /// result if a newer load superseded this one. `showLoading` drives the veil for
    /// a fresh open/navigation (not for a silent live-reload of visible content).
    private func loadTextAsync(_ target: URL, showLoading: Bool) {
        loadToken &+= 1
        let token = loadToken
        if showLoading { isLoading = true }
        let t0 = Perf.now()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rt0 = Perf.now()
            let fresh = Document.read(target)
            // Logged from the read's OWN thread → main=false proves the read is off
            // the main thread (the whole point of the fix).
            Perf.done("read.bg", since: rt0, "main=\(Thread.isMainThread) \(fresh.utf8.count)B \(target.lastPathComponent)")
            DispatchQueue.main.async {
                guard let self, token == self.loadToken else { return }   // superseded → drop
                Perf.done("read.done", since: t0, "\(fresh.utf8.count)B \(target.lastPathComponent)")
                if self.text != fresh { self.text = fresh }
                self.isLoading = false
            }
        }
    }

    /// Re-read from disk (live-reload). Scroll is preserved by the WebView host
    /// because the URL is unchanged; no loading veil for a silent refresh.
    func reload() {
        loadTextAsync(url, showLoading: false)
    }

    private func rearmWatcher() {
        watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }
}
