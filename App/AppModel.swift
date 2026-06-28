import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

/// Central app state: open tabs, the watched sidebar folder, theme, and the
/// find state. A singleton so the `AppDelegate` (file-open events) and the
/// SwiftUI scene share one instance.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Tabs
    @Published var documents: [Document] = []
    @Published var selectedID: UUID?
    @Published var draggingTabID: UUID?   // tab being drag-reordered

    /// Reorder a tab (drag-to-rearrange) — move `id` to before/at `target`'s slot.
    func moveTab(_ id: UUID, before target: UUID) {
        guard id != target,
              let from = documents.firstIndex(where: { $0.id == id }),
              let to = documents.firstIndex(where: { $0.id == target }) else { return }
        documents.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    // Theme (persisted; default dark)
    @Published var theme: AppTheme

    // Sidebar
    @Published var sidebarVisible = true
    @Published var sidebarFolder: URL
    @Published var sidebarFiles: [FileItem] = []

    // Recently opened (persisted across launches; may point outside the watched folder)
    @Published var recents: [URL] = []

    // Outline (table of contents) panel — right side; persisted, default closed.
    @Published var outlineVisible = false

    // Resizable panel widths (persisted). Drag deltas are applied from the width
    // captured at drag-start so clamping never drifts from the cursor.
    @Published var sidebarWidth: CGFloat = 248
    @Published var outlineWidth: CGFloat = 256
    private var sidebarWidthAtDragStart: CGFloat = 248
    private var outlineWidthAtDragStart: CGFloat = 256

    // Find bar
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var findCount = 0
    @Published var findIndex = 0
    @Published var findFocusToken = 0   // bump to request focus into the field

    /// The WKWebView of the front document — set by MarkdownWebView so find can drive it.
    weak var activeWebView: WKWebView?

    private var folderWatcher: FileWatcher?

    var palette: Palette { theme.palette }
    var selectedDocument: Document? { documents.first { $0.id == selectedID } }

    private init() {
        self.theme = UserDefaults.standard.string(forKey: "theme").flatMap(AppTheme.init(rawValue:)) ?? .dark
        if let saved = UserDefaults.standard.string(forKey: "sidebarFolder") {
            self.sidebarFolder = URL(fileURLWithPath: saved)
        } else {
            self.sidebarFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/plans", isDirectory: true)
        }
        if let savedRecents = UserDefaults.standard.stringArray(forKey: "recents") {
            self.recents = savedRecents.map { URL(fileURLWithPath: $0) }
        }
        self.outlineVisible = UserDefaults.standard.bool(forKey: "outlineVisible")
        let sw = UserDefaults.standard.double(forKey: "sidebarWidth")
        if sw > 0 { self.sidebarWidth = CGFloat(sw) }
        let ow = UserDefaults.standard.double(forKey: "outlineWidth")
        if ow > 0 { self.outlineWidth = CGFloat(ow) }
        reloadSidebar()
        watchFolder()
    }

    // MARK: - Opening

    func open(_ urls: [URL]) { urls.forEach { open($0) } }

    func open(_ url: URL) {
        addRecent(url)
        let key = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = documents.first(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath() == key
        }) {
            selectedID = existing.id
        } else {
            let doc = Document(url: url)
            documents.append(doc)
            selectedID = doc.id
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown"),
            UTType(filenameExtension: "mkd"),
            UTType.plainText,
            UTType.text
        ].compactMap { $0 }
        if panel.runModal() == .OK { open(panel.urls) }
    }

    // MARK: - Recents

    /// Recently opened files that still exist, most-recent first.
    var recentFiles: [URL] {
        recents.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecent(_ url: URL) {
        let std = url.standardizedFileURL
        recents.removeAll { $0.standardizedFileURL == std }
        recents.insert(std, at: 0)
        if recents.count > 12 { recents = Array(recents.prefix(12)) }
        UserDefaults.standard.set(recents.map { $0.path }, forKey: "recents")
    }

    // MARK: - Tabs

    func select(_ id: UUID) {
        selectedID = id
        hideFind()
    }

    func closeDocument(_ id: UUID) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].stop()
        documents.remove(at: idx)
        if selectedID == id {
            selectedID = documents[safe: idx]?.id ?? documents.last?.id
        }
    }

    func closeSelected() {
        if let id = selectedID { closeDocument(id) }
    }

    // MARK: - Theme

    func toggleTheme() {
        theme = (theme == .dark) ? .light : .dark
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    // MARK: - Outline

    func toggleOutline() {
        outlineVisible.toggle()
        UserDefaults.standard.set(outlineVisible, forKey: "outlineVisible")
    }

    /// Scroll the front document to a heading (no reload — the webview stays mounted).
    func scrollToHeading(_ id: String) {
        activeWebView?.evaluateJavaScript("window.__scrollToHeading(\(jsStringLiteral(id)))")
    }

    // MARK: - Panel resizing

    func beginSidebarResize() { sidebarWidthAtDragStart = sidebarWidth }
    func resizeSidebar(translation: CGFloat) {          // divider on the sidebar's right edge
        sidebarWidth = min(440, max(190, sidebarWidthAtDragStart + translation))
    }
    func beginOutlineResize() { outlineWidthAtDragStart = outlineWidth }
    func resizeOutline(translation: CGFloat) {          // divider on the outline's left edge
        outlineWidth = min(440, max(200, outlineWidthAtDragStart - translation))
    }
    func persistPanelWidths() {
        UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth")
        UserDefaults.standard.set(Double(outlineWidth), forKey: "outlineWidth")
    }

    // MARK: - Sidebar

    var sidebarFolderName: String {
        sidebarFolder.lastPathComponent.isEmpty ? sidebarFolder.path : sidebarFolder.lastPathComponent
    }

    var watchedPathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = sidebarFolder.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    func reloadSidebar() {
        let exts: Set<String> = ["md", "markdown", "txt"]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sidebarFolder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var items: [FileItem] = []
        for u in urls {
            let vals = try? u.resourceValues(forKeys: Set(keys))
            if vals?.isDirectory == true { continue }
            guard exts.contains(u.pathExtension.lowercased()) else { continue }
            items.append(FileItem(url: u, modified: vals?.contentModificationDate ?? .distantPast))
        }
        items.sort { $0.modified > $1.modified }
        sidebarFiles = items
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sidebarFolder
        if panel.runModal() == .OK, let url = panel.url {
            sidebarFolder = url
            UserDefaults.standard.set(url.path, forKey: "sidebarFolder")
            reloadSidebar()
            watchFolder()
        }
    }

    private func watchFolder() {
        folderWatcher = nil
        if FileManager.default.fileExists(atPath: sidebarFolder.path) {
            folderWatcher = FileWatcher(url: sidebarFolder) { [weak self] in
                self?.reloadSidebar()
            }
        }
    }

    // MARK: - Find

    func showFind() {
        if findVisible {
            runFind(forward: true)          // ⌘F again while open → cycle to next match
        } else {
            findVisible = true
            findFocusToken &+= 1            // focus the field + select existing text
            if !findQuery.isEmpty { runFind(forward: true, isNewQuery: true) }
        }
    }

    func hideFind() {
        findVisible = false
        activeWebView?.evaluateJavaScript("window.__clearFind && window.__clearFind()")
    }

    func findQueryChanged() {
        runFind(forward: true, isNewQuery: true)
    }

    /// Drives the renderer's JS find engine (highlights all matches + cycles the
    /// current one). isNewQuery → highlight from scratch; else next/prev.
    func runFind(forward: Bool, isNewQuery: Bool = false) {
        guard let wv = activeWebView else { return }
        let q = findQuery
        guard !q.isEmpty else {
            findCount = 0; findIndex = 0
            wv.evaluateJavaScript("window.__clearFind && window.__clearFind()")
            return
        }
        let js: String
        if isNewQuery   { js = "window.__find(\(jsStringLiteral(q)))" }
        else if forward { js = "window.__findNext()" }
        else            { js = "window.__findPrev()" }
        wv.evaluateJavaScript(js) { [weak self] res, _ in
            guard let self, let d = res as? [String: Any] else { return }
            self.findCount = (d["count"] as? Int) ?? Int((d["count"] as? Double) ?? 0)
            self.findIndex = (d["index"] as? Int) ?? Int((d["index"] as? Double) ?? 0)
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let modified: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var relative: String { relativeTime(from: modified) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
