import SwiftUI
import WebKit

/// Hosts the WKWebView that loads the bundled `reader.html` — the SAME renderer
/// the Quick Look extension uses. Swift never builds HTML; it injects the raw
/// markdown via `window.__render` and flips the theme via `window.__setTheme`.
struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var document: Document
    let theme: AppTheme
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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
        context.coordinator.apply(text: document.text, theme: theme)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var pendingText: String?
        private var pendingTheme: AppTheme?
        private var lastText: String?
        private var lastTheme: AppTheme?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        func apply(text: String, theme: AppTheme) {
            pendingText = text
            pendingTheme = theme
            if loaded { flush() }
        }

        private func flush() {
            guard let webView else { return }
            if let t = pendingTheme, t != lastTheme {
                webView.evaluateJavaScript("window.__setTheme('\(t.rawValue)')")
                lastTheme = t
            }
            if let text = pendingText, text != lastText {
                webView.evaluateJavaScript("window.__render(\(jsStringLiteral(text)))")
                lastText = text
            }
            pendingText = nil
            pendingTheme = nil
        }
    }
}
