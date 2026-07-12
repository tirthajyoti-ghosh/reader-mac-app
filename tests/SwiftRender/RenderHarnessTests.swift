import XCTest
import WebKit

/// Real-WebKit-engine checks for the shared renderer (reader.html + app.js) — the
/// same engine the app and Quick Look use. The WKWebView lives in an OFF-SCREEN
/// window: it composites (so `takeSnapshot` works) but is never key, never visible,
/// and never activates the app — so this suite is fully headless and can't steal
/// focus. reader.html is loaded straight from the repo's WebResources via #filePath.
@MainActor
final class RenderHarnessTests: XCTestCase {
    private var window: NSWindow!
    private var web: WKWebView!
    private let nav = NavCoordinator()

    private static var webResourcesURL: URL {
        // .../tests/SwiftRender/RenderHarnessTests.swift → repo root → WebResources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SwiftRender
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("WebResources", isDirectory: true)
    }

    override func setUp() async throws {
        try await super.setUp()
        let wr = Self.webResourcesURL
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        web.navigationDelegate = nav
        // Far off-screen borderless window: gives the view a backing layer to render
        // into without ever appearing on a display or becoming key.
        window = NSWindow(contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.orderBack(nil)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            nav.onFinish = { cont.resume() }
            web.loadFileURL(wr.appendingPathComponent("reader.html"), allowingReadAccessTo: wr)
        }
        _ = try await web.evaluateJavaScript("window.__applyTheme('claude-dark'); true")
    }

    override func tearDown() async throws {
        window?.orderOut(nil); window = nil; web = nil
        try await super.tearDown()
    }

    private func render(_ md: String, restoreScroll: Double = 0) async throws {
        _ = try await web.callAsyncJavaScript(
            "window.__render(md, 'harness.md', '/tmp', null, restore); return true;",
            arguments: ["md": md, "restore": restoreScroll],
            contentWorld: .page)
    }

    private func evalDouble(_ js: String) async throws -> Double {
        let r = try await web.evaluateJavaScript(js)
        return (r as? Double) ?? Double((r as? Int) ?? 0)
    }

    // MARK: tests

    func testRendersHeadingsInRealEngine() async throws {
        try await render("# One\n\nbody\n\n## Two\n\nmore\n")
        let headings = try await evalDouble("document.querySelectorAll('#doc h1, #doc h2').length")
        XCTAssertEqual(headings, 2, "expected two rendered headings")
        let h1 = try await web.evaluateJavaScript("document.querySelector('#doc h1').textContent") as? String
        XCTAssertEqual(h1?.trimmingCharacters(in: .whitespacesAndNewlines), "One")
    }

    func testScrollRestoreAppliesToContainer() async throws {
        // A tall doc so the scroll container overflows, rendered with restoreScroll=250.
        let tall = (1...200).map { "Paragraph \($0) with enough text to fill a line." }.joined(separator: "\n\n")
        try await render("# Long\n\n" + tall, restoreScroll: 250)
        // Give layout + the restore a beat to apply.
        try await Task.sleep(nanoseconds: 200_000_000)
        let top = try await evalDouble("document.getElementById('scroll').scrollTop")
        XCTAssertGreaterThan(top, 100, "restoreScroll should have scrolled the container down")
    }

    func testTakeSnapshotProducesNonEmptyImage() async throws {
        try await render("# Snapshot\n\nSome **bold** content and `code`.\n")
        try await Task.sleep(nanoseconds: 150_000_000)   // let it composite
        let cfg = WKSnapshotConfiguration()
        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            web.takeSnapshot(with: cfg) { img, err in
                if let img { cont.resume(returning: img) }
                else { cont.resume(throwing: err ?? NSError(domain: "snapshot", code: -1)) }
            }
        }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        // Non-blank: the snapshot must carry actual pixels.
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertNotNil(cg, "snapshot should yield a CGImage")
        XCTAssertGreaterThan(cg?.width ?? 0, 0)
    }
}

/// Resolves a continuation when reader.html finishes loading.
final class NavCoordinator: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?(); onFinish = nil
    }
}
