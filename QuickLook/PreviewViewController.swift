import Cocoa
import Quartz
import WebKit

/// Quick Look preview — hosts a WKWebView loading the SAME bundled reader.html as
/// the app. Designed to be snappy and to never hang:
///  • the renderer is preloaded the moment the view is created (overlaps QL setup);
///  • every step (file read, page load, render) is bounded by a timeout;
///  • the page-load wait resolves on navigation success OR failure;
///  • a short settle lets WebKit paint before Quick Look captures the view.
///
/// NOTE: the QuickLook entitlements include `com.apple.security.network.client`
/// — without it, WKWebView's networking process stalls in this sandboxed
/// extension and a local file:// load never fires didFinish (blank preview).
class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!
    private var pageReady = false
    private var readyWaiters: [() -> Void] = []

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView = WKWebView(frame: container.bounds, configuration: WKWebViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)
        self.view = container

        // Preload the renderer right away so it's ready by the time QL asks us to
        // preview a file.
        let resources = Self.resourcesURL
        webView.loadFileURL(resources.appendingPathComponent("reader.html"),
                            allowingReadAccessTo: resources)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let text = await readBounded(url, ms: 700)
        let theme = isDarkAppearance() ? "dark" : "light"
        let displayPath = Self.collapseHome(url)

        // Wait for the (preloaded) page; rendering before markdown-it loads would
        // paint nothing. Resolves on didFinish/didFail; the cap is a hang guard.
        await awaitPageReady(ms: 1500)

        let js = "window.__setTheme('\(theme)'); window.__render(\(jsLiteral(text)), \(jsLiteral(displayPath))); true"
        await evalBounded(js, ms: 700)

        // Let WebKit lay out + paint before Quick Look captures the view.
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: - Bounded helpers

    private func readBounded(_ url: URL, ms: Int) async -> String {
        await withTaskGroup(of: String?.self) { group -> String in
            group.addTask {
                (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url)) ?? ""
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? ""
        }
    }

    private func awaitPageReady(ms: Int) async {
        if pageReady { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var done = false
            let finish = { if !done { done = true; cont.resume() } }
            readyWaiters.append(finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: finish)
        }
    }

    private func evalBounded(_ js: String, ms: Int) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var done = false
            let finish = { if !done { done = true; cont.resume() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: finish)
            webView.evaluateJavaScript(js) { _, _ in finish() }
        }
    }

    private func markReady() {
        guard !pageReady else { return }
        pageReady = true
        let waiters = readyWaiters
        readyWaiters = []
        waiters.forEach { $0() }
    }

    private func isDarkAppearance() -> Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static var resourcesURL: URL {
        Bundle(for: PreviewViewController.self).resourceURL!
            .appendingPathComponent("WebResources", isDirectory: true)
    }

    private static func collapseHome(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + p.dropFirst(home.count) }
        return p
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { markReady() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { markReady() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { markReady() }
}

/// JSON-encode a string into a JS string literal for safe `evaluateJavaScript`.
private func jsLiteral(_ s: String) -> String {
    guard let data = try? JSONEncoder().encode(s),
          let str = String(data: data, encoding: .utf8) else { return "\"\"" }
    return str
}
