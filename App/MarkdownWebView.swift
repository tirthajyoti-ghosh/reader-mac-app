import SwiftUI
import WebKit
import AppKit

/// Hosts the WKWebView that loads the bundled `reader.html` — the SAME renderer
/// the Quick Look extension uses. Swift injects markdown via `window.__render`.
/// The Coordinator is also the LinkRouter: it routes link activations (a detour,
/// not a destination) so the doc webview stays mounted and scroll is preserved.
struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var document: Document
    let model: AppModel
    /// A single persistent webview renders whichever document is selected; on a
    /// tab switch it re-renders (fast) and restores that doc's saved scroll.
    var isSelected: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    // ONE of these is created for the whole app (ContentView mounts a single
    // persistent ReadingArea); documents render into it, so opens are fast.
    func makeNSView(context: Context) -> WKWebView {
        let config = WebEnv.makeConfig()
        let handler = WeakScriptHandler(context.coordinator)
        for name in ["revealFile", "link", "peek", "outline", "selchange", "scrollpos"] {
            config.userContentController.add(handler, name: name)
        }
        let webView = DocWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.hasSelection = { [weak coord = context.coordinator] in coord?.hasSelection ?? false }
        webView.onExportSelection = { [weak coord = context.coordinator] in coord?.exportSelection() }
        context.coordinator.webView = webView
        model.register(webView: webView)
        let res = Bundle.main.resourceURL!.appendingPathComponent("WebResources", isDirectory: true)
        webView.loadFileURL(res.appendingPathComponent("reader.html"), allowingReadAccessTo: res)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if isSelected { model.activeWebView = webView }
        context.coordinator.model = model
        context.coordinator.apply(document: document)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        weak var model: AppModel?
        weak var document: Document?

        private var loaded = false
        private var pendingDoc: Document?
        private var lastText: String?
        private var lastURL: URL?
        private weak var lastDoc: Document?   // the doc currently rendered (for tab-switch detection)
        var hasSelection = false          // tracked from the renderer (selectionchange)

        init(model: AppModel) { self.model = model }

        /// Right-click → Export as image…: pull the selection's rendered HTML.
        func exportSelection() {
            webView?.evaluateJavaScript("window.__selectionHTML()") { [weak self] res, _ in
                guard let self, let html = res as? String, !html.isEmpty else { NSSound.beep(); return }
                self.model?.openExport(kind: "selection", html: html)
            }
        }

        // MARK: render

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            model?.pushTheming(to: webView)   // theme id + tweaks + custom, before first render
            flush()
        }

        /// Safety net: never let an in-webview navigation destroy the doc. JS
        /// already intercepts link clicks; this catches anything that slips past.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    route(url: url, kind: kind(of: url), modifiers: navigationAction.modifierFlags)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func apply(document: Document) {
            pendingDoc = document
            self.document = document
            if loaded { flush() }
        }

        private func flush() {
            guard let webView, let doc = pendingDoc else { return }
            // A fresh open/navigation reads text off the main thread; don't paint
            // (blank or stale) while that's in flight — the loading veil covers it,
            // and we render once the read publishes `text` (which re-triggers flush).
            if doc.isLoading { pendingDoc = nil; return }
            let tabSwitch = lastDoc != nil && doc !== lastDoc      // different tab in the shared webview
            let urlChanged = doc.url != lastURL
            if doc.text != lastText || urlChanged || tabSwitch {
                let scrollArg: String
                if lastText == nil { scrollArg = "0" }              // first render ever
                else if tabSwitch { scrollArg = String(doc.savedScroll) }     // restore this doc's position
                else if urlChanged { scrollArg = String(doc.restoreScroll) }  // in-place nav / back
                else { scrollArg = "\"preserve\"" }                 // live-reload
                let bc = doc.breadcrumb.map { "{name:\(jsStringLiteral($0))}" } ?? "null"
                let t0 = Perf.now()
                webView.evaluateJavaScript(
                    "window.__render(\(jsStringLiteral(doc.text)), \(jsStringLiteral(doc.displayPath)), "
                    + "\(jsStringLiteral(doc.docDir)), \(bc), \(scrollArg))"
                ) { _, _ in Perf.done("render.jsdone", since: t0, doc.title) }
                lastText = doc.text
                lastURL = doc.url
                lastDoc = doc
            }
            pendingDoc = nil
        }

        // MARK: messages

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "revealFile":
                if let url = document?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            case "link": handleLink(message.body)
            case "peek": handlePeek(message.body)
            case "outline": handleOutline(message.body)
            case "selchange": hasSelection = (message.body as? Bool) ?? false
            case "scrollpos": if let y = (message.body as? NSNumber)?.doubleValue { document?.savedScroll = y }
            default: break
            }
        }

        /// Heading tree + scroll-spy updates from the renderer → the front doc's
        /// per-tab outline state (drives the native OutlinePanel).
        private func handleOutline(_ body: Any) {
            guard let d = body as? [String: Any], let type = d["type"] as? String else { return }
            switch type {
            case "headings":
                let items = (d["items"] as? [[String: Any]]) ?? []
                document?.headings = items.compactMap { item in
                    guard let id = item["id"] as? String, let text = item["text"] as? String else { return nil }
                    let level = (item["level"] as? Int) ?? Int((item["level"] as? Double) ?? 0)
                    return Heading(id: id, text: text, level: level)
                }
            case "active":
                document?.activeHeadingID = d["id"] as? String
            default: break
            }
        }

        private func handleLink(_ body: Any) {
            guard let d = body as? [String: Any], let event = d["event"] as? String else { return }
            switch event {
            case "back":
                document?.goBack()
            case "click":
                let kindStr = d["kind"] as? String ?? "external"
                let href = d["href"] as? String ?? ""
                let cmd = (d["cmd"] as? Bool ?? false) || (d["ctrl"] as? Bool ?? false)
                let alt = d["alt"] as? Bool ?? false
                if kindStr == "internal" {
                    if let fileURL = fileURL(fromTarget: href) {
                        withCurrentScroll { self.document?.navigate(to: fileURL, currentScroll: $0) }
                    }
                } else if let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? href) {
                    if cmd { NSWorkspace.shared.open(url); markVisited(href) }
                    else if isLocalhost(url) { NSWorkspace.shared.open(url) }
                    else if alt { openSurface(url, mode: .split); markVisited(href) }
                    else { openSurface(url, mode: .sheet); markVisited(href) }
                }
            case "contextmenu":
                showContextMenu(href: d["href"] as? String ?? "", kind: d["kind"] as? String ?? "external")
            case "peekAction":
                let action = d["action"] as? String ?? "open"
                let href = d["href"] as? String ?? ""
                let kindStr = d["kind"] as? String ?? "external"
                if kindStr == "internal", action == "open" {
                    if let fileURL = fileURL(fromTarget: href) {
                        withCurrentScroll { self.document?.navigate(to: fileURL, currentScroll: $0) }
                    }
                } else if let url = URL(string: href) {
                    switch action {
                    case "browser": NSWorkspace.shared.open(url)
                    case "split": openSurface(url, mode: .split); markVisited(href)
                    default: openSurface(url, mode: .sheet); markVisited(href)
                    }
                }
            default: break
            }
        }

        private func handlePeek(_ body: Any) {
            guard let d = body as? [String: Any], let id = d["id"] as? Int,
                  let href = d["href"] as? String else { return }
            let kindStr = d["kind"] as? String ?? "external"
            if kindStr == "internal" {
                guard let fileURL = fileURL(fromTarget: href) else { return }
                // Read off the main thread — a hover preview must never hang the UI.
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let text = Document.read(fileURL)
                    DispatchQueue.main.async {
                        self?.sendPeek(id, ["href": href, "kind": "internal",
                                            "domain": Document.displayPath(for: fileURL),
                                            "snippet": self?.snippet(of: text) ?? ""])
                    }
                }
            } else if let url = URL(string: href) {
                MetadataFetcher.shared.fetch(url) { [weak self] meta in
                    self?.sendPeek(id, meta.peekDictionary(href: href))
                }
            }
        }

        // MARK: routing helpers

        private func route(url: URL, kind: String, modifiers: NSEvent.ModifierFlags) {
            if modifiers.contains(.command) { NSWorkspace.shared.open(url); return }
            if kind == "internal" {
                withCurrentScroll { self.document?.navigate(to: url, currentScroll: $0) }
            } else if isLocalhost(url) {
                NSWorkspace.shared.open(url)
            } else if modifiers.contains(.option) {
                openSurface(url, mode: .split)
            } else {
                openSurface(url, mode: .sheet)
            }
        }

        private func openSurface(_ url: URL, mode: LinkSurface.Mode) {
            model?.settingsOpen = false      // a detour wins over the settings popover
            model?.exportOpen = false
            document?.surface = LinkSurface(url: url, mode: mode)
        }

        private func withCurrentScroll(_ then: @escaping (Double) -> Void) {
            webView?.evaluateJavaScript("window.__getScroll()") { res, _ in
                let top = (res as? Double) ?? Double((res as? Int) ?? 0)
                then(top)
            }
        }

        private func markVisited(_ href: String) {
            webView?.evaluateJavaScript("window.__markVisited(\(jsStringLiteral(href)))")
        }

        private func sendPeek(_ id: Int, _ data: [String: Any]) {
            guard let json = try? JSONSerialization.data(withJSONObject: data),
                  let s = String(data: json, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.__peekResult(\(id), \(s))")
        }

        private func kind(of url: URL) -> String {
            if url.isFileURL && url.pathExtension.lowercased().hasPrefix("md") { return "internal" }
            return "external"
        }

        private func fileURL(fromTarget target: String) -> URL? {
            var path = target
            if let h = path.firstIndex(of: "#") { path = String(path[..<h]) }
            guard !path.isEmpty else { return nil }
            if path.hasPrefix("file://") { return URL(string: path) }
            return URL(fileURLWithPath: path)
        }

        private func isLocalhost(_ url: URL) -> Bool {
            let h = (url.host ?? "").lowercased()
            return h == "localhost" || h == "127.0.0.1" || h == "0.0.0.0" || h.hasSuffix(".localhost")
        }

        private func snippet(of text: String) -> String {
            // first ~700 chars, ending on a paragraph boundary if possible
            let head = String(text.prefix(700))
            if let r = head.range(of: "\n\n", options: .backwards), head.count > 200 {
                return String(head[..<r.lowerBound])
            }
            return head
        }

        private func showContextMenu(href: String, kind: String) {
            let menu = NSMenu()
            let isInternal = kind == "internal"
            menu.addItem(ClosureMenuItem(isInternal ? "Open" : "Open in sheet") { [weak self] in
                guard let self else { return }
                if isInternal, let f = self.fileURL(fromTarget: href) {
                    self.withCurrentScroll { self.document?.navigate(to: f, currentScroll: $0) }
                } else if let url = URL(string: href) { self.openSurface(url, mode: .sheet) }
            })
            if !isInternal {
                menu.addItem(ClosureMenuItem("Open in split") { [weak self] in
                    if let url = URL(string: href) { self?.openSurface(url, mode: .split) }
                })
                menu.addItem(ClosureMenuItem("Open in browser") {
                    if let url = URL(string: href) { NSWorkspace.shared.open(url) }
                })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(href, forType: .string)
            })
            if let view = webView {
                menu.popUp(positioning: nil, at: view.convert(NSEvent.mouseLocation, from: nil), in: view)
            }
        }
    }
}

/// Weak wrapper so the WKUserContentController doesn't retain the Coordinator.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// NSMenuItem with a closure action.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// WKWebView subclass that adds "Export as image…" to the context menu when the
/// user right-clicks a text selection in the doc (Track S §8.3.3).
final class DocWebView: WKWebView {
    var hasSelection: () -> Bool = { false }
    var onExportSelection: (() -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard hasSelection() else { return }
        let item = NSMenuItem(title: "Export as image…", action: #selector(exportSelectionAction), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
    @objc private func exportSelectionAction() { onExportSelection?() }
}
