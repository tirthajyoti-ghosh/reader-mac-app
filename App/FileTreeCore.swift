import Foundation

/// One entry in a folder listing (a file or a subfolder). Pure value type — no UI,
/// no Combine — so the enumeration/sort/filter rules are unit-testable on their own.
struct TreeEntry: Equatable {
    let url: URL
    let name: String
    let isDir: Bool
}

/// The rules that decide what the file tree shows: which files/folders are included,
/// how they sort, and what a filter matches. Foundation-only + deterministic.
enum TreeCore {
    /// Markdown/plain-text files the reader can open (matches the flat sidebar's set).
    static let fileExtensions: Set<String> = ["md", "markdown", "txt"]

    /// Directories we never descend into or show — noise, VCS internals, or macOS
    /// package bundles (which are directories but should read as opaque files).
    static let excludedDirNames: Set<String> = ["node_modules", ".git"]
    static let bundleExtensions: Set<String> = [
        "app", "bundle", "framework", "xcodeproj", "xcworkspace", "playground",
        "photoslibrary", "rtfd", "lproj", "xcassets", "appex", "kext", "plugin"
    ]

    /// A directory is excluded if it's a known noise folder or a package bundle.
    static func isExcludedDir(name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if excludedDirNames.contains(name) { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && bundleExtensions.contains(ext)
    }

    static func isReadableFile(name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        return fileExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Sort: folders first, then files, each alphabetically case-insensitively
    /// (Finder-style, so "file2" < "file10").
    static func sorted(_ entries: [TreeEntry]) -> [TreeEntry] {
        entries.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }           // folders before files
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The immediate children of `dir` that the tree should show — matching files
    /// and non-excluded subfolders — sorted. Synchronous disk I/O; callers run it
    /// off the main thread.
    static func children(of dir: URL, fileManager: FileManager = .default) -> [TreeEntry] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var out: [TreeEntry] = []
        out.reserveCapacity(urls.count)
        for url in urls {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if isExcludedDir(name: name) { continue }
                out.append(TreeEntry(url: url, name: name, isDir: true))
            } else if isReadableFile(name: name) {
                out.append(TreeEntry(url: url, name: name, isDir: false))
            }
        }
        return sorted(out)
    }

    /// Case-insensitive substring match for the filter. Empty query matches nothing
    /// special — callers treat "" as "no filter".
    static func matches(name: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The [start, end) range of the first filter match in `name`, for highlighting.
    static func matchRange(name: String, query: String) -> Range<String.Index>? {
        guard !query.isEmpty else { return nil }
        return name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }
}
