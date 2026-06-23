import Foundation
import Combine

/// One open document = a tab. Reads its file on init and live-reloads via a
/// `FileWatcher` (kqueue), re-publishing `text` so the bound WKWebView re-renders.
final class Document: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var title: String
    @Published var text: String

    private var watcher: FileWatcher?

    init(url: URL) {
        self.url = url
        self.title = url.lastPathComponent
        self.text = Document.read(url)
        self.watcher = FileWatcher(url: url) { [weak self] in
            self?.reload()
        }
    }

    static func read(_ url: URL) -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return (try? String(contentsOf: url)) ?? ""
    }

    /// Re-read from disk; only republishes if the content actually changed.
    func reload() {
        let fresh = Document.read(url)
        if fresh != text { text = fresh }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }
}
