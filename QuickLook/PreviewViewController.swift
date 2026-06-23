import Cocoa
import Quartz
import WebKit

/// Quick Look preview: hosts a WKWebView loading the SAME bundled reader.html as
/// the app, so a spacebar preview and an open tab render identically. We await
/// both the page load AND the render eval before returning, so Quick Look
/// snapshots the fully painted result.
class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!
    private var loadContinuation: CheckedContinuation<Void, Never>?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView = WKWebView(frame: container.bounds, configuration: WKWebViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)
        self.view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url)) ?? ""
        let theme = isDarkAppearance() ? "dark" : "light"

        let resources = Bundle(for: PreviewViewController.self).resourceURL!
            .appendingPathComponent("WebResources", isDirectory: true)
        let reader = resources.appendingPathComponent("reader.html")

        // 1) load reader.html, wait for didFinish
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.loadContinuation = cont
            self.webView.loadFileURL(reader, allowingReadAccessTo: resources)
        }

        // 2) inject theme + content (with the home-collapsed path), await the eval
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let abs = url.path
        let displayPath = abs == home ? "~"
            : (abs.hasPrefix(home + "/") ? "~" + abs.dropFirst(home.count) : abs)
        let js = "window.__setTheme('\(theme)'); window.__render(\(jsLiteral(text)), \(jsLiteral(displayPath))); true"
        _ = try? await webView.evaluateJavaScript(js)

        // 3) give Mermaid / KaTeX a beat to paint before the snapshot
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func isDarkAppearance() -> Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

/// JSON-encode a string into a JS string literal for safe `evaluateJavaScript`.
private func jsLiteral(_ s: String) -> String {
    guard let data = try? JSONEncoder().encode(s),
          let str = String(data: data, encoding: .utf8) else { return "\"\"" }
    return str
}
