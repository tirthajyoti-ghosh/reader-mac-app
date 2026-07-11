import WebKit

/// Shared WebKit environment. All doc webviews (and the export webview) share ONE
/// process pool, so only the FIRST webview pays the WebContent-process spawn; the
/// rest are warm. `warm()` spins that process up at launch (while the empty state
/// is on screen) and primes the file cache for reader.html + the vendored JS, so
/// the user's first sidebar-open is warm instead of cold (~130ms vs ~220ms).
enum WebEnv {
    static let pool = WKProcessPool()
    private static var warmer: WKWebView?

    static func makeConfig() -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.processPool = pool
        return cfg
    }

    static func warm() {
        guard warmer == nil else { return }
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 240), configuration: makeConfig())
        let res = Bundle.main.resourceURL!.appendingPathComponent("WebResources", isDirectory: true)
        wv.loadFileURL(res.appendingPathComponent("reader.html"), allowingReadAccessTo: res)
        warmer = wv   // keep it alive so the process + cache stay warm
    }
}
