import WebKit

/// Shared WebKit environment. The doc webview and the export webview share ONE
/// process pool, so only the first pays the WebContent-process spawn.
enum WebEnv {
    static let pool = WKProcessPool()

    static func makeConfig() -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.processPool = pool
        return cfg
    }
}
