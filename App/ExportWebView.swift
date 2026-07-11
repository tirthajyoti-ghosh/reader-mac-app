import SwiftUI
import WebKit

/// The Track S (§8.3.3) capture surface: a dedicated WKWebView loading the SAME
/// `reader.html`, shown live (scaled) as the dialog preview AND used as the
/// `takeSnapshot` source. The card is built from ALREADY-RENDERED `.md` HTML
/// (Mermaid = live SVG, KaTeX = glyphs, code highlighted), and theme/tweaks/preset
/// are pushed onto documentElement — so WebKit's own painter rasterizes the
/// export exactly as it looks on screen. No serialization, no font/colour loss.
struct ExportWebView: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coord { Coord(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WebEnv.makeConfig()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = wv
        model.exportWebView = wv
        let res = Bundle.main.resourceURL!.appendingPathComponent("WebResources", isDirectory: true)
        wv.loadFileURL(res.appendingPathComponent("reader.html"), allowingReadAccessTo: res)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        context.coordinator.model = model
        context.coordinator.rebuild()
    }

    final class Coord: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var model: AppModel
        private var loaded = false
        private var lastSig = ""
        init(model: AppModel) { self.model = model }

        func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
            loaded = true
            model.pushExportTheming(to: wv)
            rebuild(force: true)
        }

        /// (Re)build the card in the webview + measure it. Idempotent — only runs
        /// when the relevant state changed, so SwiftUI re-renders are cheap.
        func rebuild(force: Bool = false) {
            guard loaded, let wv = webView else { return }
            let t = model.tweaks.map { "\($0)=\($1)" }.sorted().joined(separator: ",")
            let sig = "\(model.themeId)|\(model.exportPadding)|\(model.exportWidth)|\(model.exportShadow)|\(model.readingPreset ?? "")|\(t)|\(model.exportHTML.hashValue)"
            if !force && sig == lastSig { return }
            lastSig = sig
            model.pushExportTheming(to: wv)
            let opts: [String: Any] = ["snug": model.exportPadding == "snug",
                                       "width": model.exportWidth,
                                       "shadow": model.exportShadow]
            let js = "window.__buildExportCard(html, opts); await document.fonts.ready; return window.__exportSize();"
            wv.callAsyncJavaScript(js, arguments: ["html": model.exportHTML, "opts": opts],
                                   in: nil, in: .page) { [weak self] result in
                guard let self, case let .success(v) = result, let d = v as? [String: Any],
                      let w = (d["w"] as? NSNumber)?.doubleValue, let h = (d["h"] as? NSNumber)?.doubleValue,
                      w > 0, h > 0 else { return }
                DispatchQueue.main.async { self.model.exportCardSize = CGSize(width: w, height: h) }
            }
        }
    }
}
