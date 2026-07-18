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

    // Theme (Track T §8.3.1): a theme id (themes.css) + live single-token tweaks +
    // optional imported custom theme. The chrome palette is dynamic — derived from
    // the active theme so the whole app retints per theme.
    @Published var themeId: String
    @Published var tweaks: [String: String] = [:]
    @Published var customCSS: String?
    @Published var settingsOpen = false
    @Published private(set) var palette: Palette = .dark
    let builtinThemes: [BuiltinTheme]
    private let liveWebViews = NSHashTable<WKWebView>.weakObjects()

    // Track A11y (§8.3.2) reading/focus modes — all default OFF (I4). Face +
    // letter/word spacing + focus-dim reuse `tweaks`; these are separate modes.
    @Published var lineFocus = false
    @Published var dimParagraphs = false
    @Published var bionic = false
    @Published var readingPreset: String?   // "sepia" | "high-contrast" | nil
    /// Which tweak tokens each section's Reset owns (both live in `tweaks`).
    static let themeTokenKeys = ["--accent", "--md-max", "--leading", "--fs-base", "--para-space"]
    static let a11yTokenKeys  = ["--font", "--letter-spacing", "--word-spacing", "--focus-dim"]

    // Sidebar
    @Published var sidebarVisible = true
    @Published var sidebarFolder: URL
    /// The nested file tree (Track F, §8.1.3) — replaces the old flat single-level list.
    let tree = TreeStore()

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

    var selectedDocument: Document? { documents.first { $0.id == selectedID } }
    /// Blank doc that keeps the single reading webview mounted before any file opens.
    let placeholderDoc = Document()

    private init() {
        self.themeId = UserDefaults.standard.string(forKey: "themeId") ?? "claude-dark"
        self.builtinThemes = Theming.parse(Theming.loadThemesCSS())
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
        if let t = UserDefaults.standard.dictionary(forKey: "themeTweaks") as? [String: String] { self.tweaks = t }
        self.customCSS = UserDefaults.standard.string(forKey: "customThemeCSS")
        self.lineFocus = UserDefaults.standard.bool(forKey: "a11yLineFocus")
        self.dimParagraphs = UserDefaults.standard.bool(forKey: "a11yDimParagraphs")
        self.bionic = UserDefaults.standard.bool(forKey: "a11yBionic")
        self.readingPreset = UserDefaults.standard.string(forKey: "readingPreset")
        self.exportPadding = UserDefaults.standard.string(forKey: "exportPadding") ?? "comfortable"
        self.exportWidth = UserDefaults.standard.string(forKey: "exportWidth") ?? "social"
        self.exportShadow = (UserDefaults.standard.object(forKey: "exportShadow") as? Bool) ?? true
        tree.setRoot(sidebarFolder)
        updatePalette()
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
        tree.reveal(url)                       // select + scroll the row into view
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

    // MARK: - Theme (Track T)

    var activeTheme: BuiltinTheme? { builtinThemes.first { $0.id == themeId } }
    var colorScheme: ColorScheme { (activeTheme?.isLight ?? false) ? .light : .dark }

    /// Recompute the native chrome palette from the active theme (+ accent tweak).
    func updatePalette() {
        let t = activeTheme ?? builtinThemes.first(where: { $0.id == "claude-dark" })
        guard let t else { palette = .dark; return }
        palette = Palette.from(t.colors, isLight: t.isLight, accentHex: tweaks["--accent"])
    }

    /// A newly-loaded webview: sync it to the current theme + tweaks + custom theme.
    func register(webView: WKWebView) { liveWebViews.add(webView) }
    func pushTheming(to wv: WKWebView) {
        wv.evaluateJavaScript("window.__applyTheme('\(themeId)')")
        if let css = customCSS { wv.evaluateJavaScript("window.__applyCustom(\(jsStringLiteral(css)))") }
        for (k, v) in tweaks { wv.evaluateJavaScript("window.__setOverride('\(k)', \(jsStringLiteral(v)))") }
        // Track A11y modes + preset (re-applied on every fresh webview / render).
        if lineFocus { wv.evaluateJavaScript("window.__setLineFocus(true)") }
        if dimParagraphs { wv.evaluateJavaScript("window.__setDimParagraphs(true)") }
        if bionic { wv.evaluateJavaScript("window.__setBionic(true)") }
        if let p = readingPreset { wv.evaluateJavaScript("window.__applyReadingPreset('\(p)')") }
    }
    private func evalAll(_ js: String) { for wv in liveWebViews.allObjects { wv.evaluateJavaScript(js) } }

    func selectTheme(_ id: String) {
        guard id != themeId else { return }
        themeId = id
        UserDefaults.standard.set(id, forKey: "themeId")
        evalAll("window.__applyTheme('\(id)')")
        updatePalette()
    }
    /// Sun/moon: flip the current theme's light↔dark pair (fall back to Claude).
    func toggleTheme() {
        selectTheme(Theming.pairs[themeId] ?? (colorScheme == .dark ? "claude-light" : "claude-dark"))
    }

    // MARK: - No-code tweaks (single-token overrides, live + persisted)

    func setTweak(_ token: String, _ value: String) {
        tweaks[token] = value
        UserDefaults.standard.set(tweaks, forKey: "themeTweaks")
        evalAll("window.__setOverride('\(token)', \(jsStringLiteral(value)))")
        if token == "--accent" { updatePalette() }
    }
    func clearTweak(_ token: String) {
        guard tweaks[token] != nil else { return }
        tweaks[token] = nil
        UserDefaults.standard.set(tweaks, forKey: "themeTweaks")
        evalAll("window.__clearOverride('\(token)')")
        if token == "--accent" { updatePalette() }
    }
    /// Theme section Reset — clears only the theme tweaks (A11y tweaks are separate).
    func clearAllTweaks() {
        let hit = Self.themeTokenKeys.filter { tweaks[$0] != nil }
        guard !hit.isEmpty else { return }
        for t in hit { tweaks[t] = nil; evalAll("window.__clearOverride('\(t)')") }
        UserDefaults.standard.set(tweaks, forKey: "themeTweaks")
        updatePalette()
    }
    var hasThemeTweaks: Bool { Self.themeTokenKeys.contains { tweaks[$0] != nil } }

    // MARK: - Reading / accessibility (Track A11y §8.3.2)

    func setLineFocus(_ on: Bool) {
        guard on != lineFocus else { return }
        lineFocus = on
        UserDefaults.standard.set(on, forKey: "a11yLineFocus")
        evalAll("window.__setLineFocus(\(on))")
    }
    func setDimParagraphs(_ on: Bool) {
        guard on != dimParagraphs else { return }
        dimParagraphs = on
        UserDefaults.standard.set(on, forKey: "a11yDimParagraphs")
        evalAll("window.__setDimParagraphs(\(on))")
    }
    func setBionic(_ on: Bool) {
        guard on != bionic else { return }
        bionic = on
        UserDefaults.standard.set(on, forKey: "a11yBionic")
        evalAll("window.__setBionic(\(on))")
    }
    func setReadingPreset(_ name: String?) {
        guard name != readingPreset else { return }
        readingPreset = name
        if let n = name {
            UserDefaults.standard.set(n, forKey: "readingPreset")
            evalAll("window.__applyReadingPreset('\(n)')")
        } else {
            UserDefaults.standard.removeObject(forKey: "readingPreset")
            evalAll("window.__clearReadingPreset()")
        }
    }
    /// Reading section Reset — clears the A11y tweaks + all A11y modes.
    func resetReading() {
        for t in Self.a11yTokenKeys where tweaks[t] != nil {
            tweaks[t] = nil; evalAll("window.__clearOverride('\(t)')")
        }
        UserDefaults.standard.set(tweaks, forKey: "themeTweaks")
        setLineFocus(false); setDimParagraphs(false); setBionic(false); setReadingPreset(nil)
    }
    var hasReadingSettings: Bool {
        lineFocus || dimParagraphs || bionic || readingPreset != nil
            || Self.a11yTokenKeys.contains { tweaks[$0] != nil }
    }

    // MARK: - Image export (Track S §8.3.3)

    @Published var exportOpen = false
    @Published var exportKind = ""            // "selection" | "document" — subtitle only
    @Published var exportHTML = ""            // the already-rendered .md HTML to frame
    @Published var exportPadding = "comfortable"  // "snug" | "comfortable"
    @Published var exportWidth = "social"         // "social" | "docs"
    @Published var exportShadow = true
    @Published var exportCardSize = CGSize(width: 1080, height: 480)
    weak var exportWebView: WKWebView?

    /// Export webview theming = theme + tweaks + custom + preset (NOT the focus
    /// modes — an export reflects the palette/ergonomics, not line-focus/bionic).
    func pushExportTheming(to wv: WKWebView) {
        wv.evaluateJavaScript("window.__applyTheme('\(themeId)')")
        if let css = customCSS { wv.evaluateJavaScript("window.__applyCustom(\(jsStringLiteral(css)))") }
        for (k, v) in tweaks { wv.evaluateJavaScript("window.__setOverride('\(k)', \(jsStringLiteral(v)))") }
        if let p = readingPreset { wv.evaluateJavaScript("window.__applyReadingPreset('\(p)')") }
    }

    func openExport(kind: String, html: String) {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        exportKind = kind
        exportHTML = html
        settingsOpen = false                 // mutually exclusive (Track T pattern)
        selectedDocument?.surface = nil
        exportOpen = true
    }
    func closeExport() { exportOpen = false }
    /// Toolbar ⋯ → Export whole document…: grab the front doc's rendered HTML.
    func exportWholeDocument() {
        guard let wv = activeWebView else { NSSound.beep(); return }
        wv.evaluateJavaScript("window.__docHTML()") { [weak self] res, _ in
            guard let self, let html = res as? String, !html.isEmpty else { NSSound.beep(); return }
            self.openExport(kind: "document", html: html)
        }
    }

    func setExportPadding(_ v: String) { exportPadding = v; UserDefaults.standard.set(v, forKey: "exportPadding") }
    func setExportWidth(_ v: String)   { exportWidth = v;   UserDefaults.standard.set(v, forKey: "exportWidth") }
    func setExportShadow(_ v: Bool)    { exportShadow = v;  UserDefaults.standard.set(v, forKey: "exportShadow") }

    /// Capture the framed card as a 2× (retina) PNG via WebKit's own painter.
    func captureExport(_ completion: @escaping (NSImage?) -> Void) {
        guard let wv = exportWebView else { return completion(nil) }
        let w = exportCardSize.width, h = exportCardSize.height
        guard w > 0, h > 0 else { return completion(nil) }
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: 0, y: 0, width: w, height: h)
        let scale = wv.window?.backingScaleFactor ?? 2
        cfg.snapshotWidth = NSNumber(value: Double(w * CGFloat(Self.exportScale) / scale))  // → 2× pixels
        wv.takeSnapshot(with: cfg) { image, _ in completion(image) }
    }
    static let exportScale: Int = 2
    static func pngData(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
    func copyExport() {
        captureExport { img in
            guard let img, let png = Self.pngData(img) else { NSSound.beep(); return }
            let pb = NSPasteboard.general; pb.clearContents(); pb.setData(png, forType: .png)
        }
    }
    func saveExport() {
        captureExport { img in
            guard let img, let png = Self.pngData(img) else { NSSound.beep(); return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.png]
            panel.nameFieldStringValue = "reader-export.png"
            if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
        }
    }

    // MARK: - Custom theme import (§8.5.1 security: token declarations only)

    /// Returns an error message on rejection, or nil on success. (Validation lives
    /// in `Theming.validateCustomTheme` — pure + unit-tested.)
    func importCustomTheme(_ url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return "Couldn't read the file." }
        let (css, error) = Theming.validateCustomTheme(raw)
        guard let css else { return error }
        customCSS = css
        UserDefaults.standard.set(css, forKey: "customThemeCSS")
        evalAll("window.__applyCustom(\(jsStringLiteral(css)))")
        return nil
    }
    func clearCustomTheme() {
        customCSS = nil
        UserDefaults.standard.removeObject(forKey: "customThemeCSS")
        evalAll("window.__clearCustom()")
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    // MARK: - Outline

    func toggleOutline() {
        outlineVisible.toggle()
        UserDefaults.standard.set(outlineVisible, forKey: "outlineVisible")
    }

    /// Settings popover ↔ a link sheet ↔ export dialog are mutually exclusive.
    func toggleSettings() {
        settingsOpen.toggle()
        if settingsOpen { selectedDocument?.surface = nil; exportOpen = false }
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

    /// Refresh button / ⌘R → re-read the visible tree (the tree keeps its own
    /// recursive FSEvents watcher for live changes).
    func reloadSidebar() { tree.refresh() }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sidebarFolder
        if panel.runModal() == .OK, let url = panel.url {
            sidebarFolder = url
            UserDefaults.standard.set(url.path, forKey: "sidebarFolder")
            tree.setRoot(url)
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
