import SwiftUI
import WebKit
import AppKit

/// Hosts the WKWebView that loads the bundled `reader.html` — the SAME renderer
/// the Quick Look extension uses. Swift never builds HTML; it injects the raw
/// markdown via `window.__render(text, path)` and flips the theme via
/// `window.__setTheme`.
struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var document: Document
    let theme: AppTheme
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Lets the .doc-path caption reveal the file in Finder on click.
        config.userContentController.add(WeakScriptHandler(context.coordinator), name: "revealFile")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        // Let the themed page background paint (avoids a white flash before load).
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        let resources = Bundle.main.resourceURL!
            .appendingPathComponent("WebResources", isDirectory: true)
        let reader = resources.appendingPathComponent("reader.html")
        webView.loadFileURL(reader, allowingReadAccessTo: resources)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        model.activeWebView = webView
        context.coordinator.apply(text: document.text,
                                  path: document.displayPath,
                                  url: document.url,
                                  theme: theme)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var currentURL: URL?
        private var loaded = false
        private var pendingText: String?
        private var pendingPath: String?
        private var pendingTheme: AppTheme?
        private var lastText: String?
        private var lastPath: String?
        private var lastTheme: AppTheme?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        func apply(text: String, path: String, url: URL, theme: AppTheme) {
            pendingText = text
            pendingPath = path
            currentURL = url
            pendingTheme = theme
            if loaded { flush() }
        }

        private func flush() {
            guard let webView else { return }
            if let t = pendingTheme, t != lastTheme {
                webView.evaluateJavaScript("window.__setTheme('\(t.rawValue)')")
                lastTheme = t
            }
            if let text = pendingText, text != lastText || pendingPath != lastPath {
                let path = pendingPath ?? ""
                webView.evaluateJavaScript("window.__render(\(jsStringLiteral(text)), \(jsStringLiteral(path)))")
                lastText = text
                lastPath = pendingPath
            }
            pendingText = nil
            pendingPath = nil
            pendingTheme = nil
        }

        // Reveal-in-Finder from the .doc-path caption.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "revealFile", let url = currentURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// Weak wrapper so the WKUserContentController doesn't retain the Coordinator
/// (which would create a webView ⇄ coordinator cycle).
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
