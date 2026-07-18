import XCTest

/// Unit tests for the pure file-tree rules (TreeCore) — enumeration filtering,
/// folders-first Finder-style sort, exclusions, and filter matching. Runs against a
/// real temp directory so the FileManager path is exercised, but stays host-less.
final class FileTreeCoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("treecore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ name: String) throws {
        try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func mkdir(_ name: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    func testIncludesMarkdownAndTextAndSubfolders() throws {
        try touch("notes.md"); try touch("plain.txt"); try touch("doc.markdown")
        try touch("image.png"); try touch("data.json")
        try mkdir("sub")
        let names = TreeCore.children(of: root).map(\.name)
        XCTAssertEqual(Set(names), ["sub", "notes.md", "plain.txt", "doc.markdown"])
        XCTAssertFalse(names.contains("image.png"))
        XCTAssertFalse(names.contains("data.json"))
    }

    func testFoldersFirstThenFinderStyleSort() throws {
        try touch("file10.md"); try touch("file2.md"); try touch("Apple.md")
        try mkdir("zeta"); try mkdir("alpha")
        let entries = TreeCore.children(of: root)
        // folders first (alpha, zeta), then files (Apple, file2, file10 — natural order)
        XCTAssertEqual(entries.map(\.name), ["alpha", "zeta", "Apple.md", "file2.md", "file10.md"])
        XCTAssertTrue(entries[0].isDir && entries[1].isDir)
    }

    func testExcludesDotfilesNodeModulesGitAndBundles() throws {
        try touch(".hidden.md")
        try mkdir(".git"); try mkdir("node_modules"); try mkdir("Thing.app"); try mkdir("real")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        let names = Set(TreeCore.children(of: root).map(\.name))
        XCTAssertEqual(names, ["real"])
        XCTAssertFalse(names.contains(".git"))
        XCTAssertFalse(names.contains("node_modules"))
        XCTAssertFalse(names.contains("Thing.app"))
        XCTAssertFalse(names.contains(".hidden.md"))
    }

    func testEmptyAndMissingFolders() throws {
        XCTAssertTrue(TreeCore.children(of: root).isEmpty)
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        XCTAssertTrue(TreeCore.children(of: missing).isEmpty)   // no throw on missing dir
    }

    func testMatchesIsCaseAndDiacriticInsensitive() {
        XCTAssertTrue(TreeCore.matches(name: "Caching-Strategies.md", query: "cach"))
        XCTAssertTrue(TreeCore.matches(name: "résumé.md", query: "resume"))
        XCTAssertFalse(TreeCore.matches(name: "kafka.md", query: "spark"))
        XCTAssertTrue(TreeCore.matches(name: "anything", query: ""))   // empty = no filter
    }

    func testMatchRangeLocatesSubstring() {
        let name = "consistent-hashing.md"
        let r = TreeCore.matchRange(name: name, query: "hash")
        XCTAssertNotNil(r)
        XCTAssertEqual(r.map { String(name[$0]) }, "hash")
        XCTAssertNil(TreeCore.matchRange(name: name, query: "xyz"))
    }
}
