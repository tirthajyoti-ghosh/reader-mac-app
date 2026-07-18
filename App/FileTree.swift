import SwiftUI

/// One rendered line in the tree (already flattened for display + keyboard nav).
struct TreeRow: Identifiable, Equatable {
    enum Kind: Equatable { case file, folder, empty, noMatch }
    let id: String
    let url: URL          // for .empty/.noMatch this is a synthetic marker URL
    let name: String
    let depth: Int
    let kind: Kind
    let isOpen: Bool
}

/// Drives the sidebar file tree: LAZY enumeration (a folder's children are read only
/// when it's shown/expanded, off the main thread, cached), hide-empty via a shallow
/// one-level peek, an async cancellable filter that auto-expands to matches, reveal
/// (expand ancestors + scroll) when a file opens from anywhere, tree-aware watching
/// (a single recursive FSEventStream), and per-root persistence of expansion + scroll.
///
/// Everything is keyed by a normalized path STRING (`key(_:)`) — directory URLs carry
/// trailing slashes and `/tmp` is a symlink, so URL identity is unreliable.
///
/// Lives on the main thread (AppModel owns it); all disk I/O hops to a background
/// queue and republishes on main.
final class TreeStore: ObservableObject {
    @Published private(set) var rows: [TreeRow] = []
    @Published var filter: String = "" { didSet { if filter != oldValue { onFilterChanged() } } }
    @Published private(set) var isFiltering = false
    @Published var focusedID: String?               // keyboard focus ring (≠ opened file)
    /// Bumped to ask the view to scroll a row into view (reveal / keyboard nav).
    @Published private(set) var scrollTarget: (id: String, tick: Int)?

    private(set) var root: URL?
    private var expanded: Set<String> = []
    private var childrenCache: [String: [TreeEntry]] = [:]   // nil = not enumerated yet
    private var enumerating: Set<String> = []
    private var watcher: FolderTreeWatcher?
    private var filterTask: Task<Void, Never>?
    private var tick = 0

    private let maxFilterResults = 3000

    private func key(_ url: URL) -> String { url.standardizedFileURL.path }

    // MARK: - Root

    func setRoot(_ url: URL) {
        let std = url.standardizedFileURL
        if root?.standardizedFileURL == std { return }
        filterTask?.cancel(); isFiltering = false
        if filter != "" { filter = "" }
        root = std
        expanded = loadExpanded(for: std)
        childrenCache = [:]; enumerating = []
        focusedID = nil
        watcher = FolderTreeWatcher(root: std) { [weak self] dirs in
            self?.handleFSEvents(dirs)          // FolderTreeWatcher delivers on main
        }
        ensure(std)
        rebuildRows()
    }

    // MARK: - Expand / collapse

    func toggle(_ url: URL) {
        let k = key(url)
        if expanded.contains(k) { expanded.remove(k) }
        else { expanded.insert(k); ensure(url) }
        saveExpanded()
        rebuildRows()
    }
    func isExpanded(_ url: URL) -> Bool { expanded.contains(key(url)) }

    /// Refresh button / ⌘R: drop caches, re-enumerate what's visible, keep expansion.
    func refresh() {
        guard let root else { return }
        childrenCache = [:]; enumerating = []
        ensure(root)
        rebuildRows()
    }

    // MARK: - Reveal (open-from-anywhere → select + scroll into view)

    func reveal(_ url: URL) {
        guard let root else { return }
        let target = url.standardizedFileURL
        let rootKey = key(root)
        guard key(target).hasPrefix(rootKey) else { return }     // outside the watched tree
        // Expand every ancestor folder between the file and the root.
        var dir = target.deletingLastPathComponent().standardizedFileURL
        while key(dir).count >= rootKey.count {
            let k = key(dir)
            if k != rootKey { expanded.insert(k) }
            ensure(dir)
            if k == rootKey { break }
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
        saveExpanded()
        focusedID = key(target)
        rebuildRows()
        requestScroll(to: key(target))
    }

    private func requestScroll(to id: String) { tick += 1; scrollTarget = (id, tick) }

    // MARK: - Lazy enumeration

    /// Ensure `dir`'s children are cached; enumerate off the main thread if not.
    private func ensure(_ dir: URL) {
        let k = key(dir)
        guard childrenCache[k] == nil, !enumerating.contains(k) else { return }
        enumerating.insert(k)
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = TreeCore.children(of: dir)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.enumerating.remove(k)
                self.childrenCache[k] = entries
                if !self.isFiltering { self.rebuildRows() }
            }
        }
    }

    // MARK: - Row building (lazy, non-filter)

    private func rebuildRows() {
        guard !isFiltering, let root else { return }
        var out: [TreeRow] = []
        walk(root, depth: 0, into: &out)
        rows = out
        clampFocus()
    }

    private func walk(_ dir: URL, depth: Int, into out: inout [TreeRow]) {
        guard let entries = childrenCache[key(dir)] else { ensure(dir); return }
        for e in entries {
            if e.isDir {
                let open = expanded.contains(key(e.url))
                if let kids = childrenCache[key(e.url)] {
                    // shallow peek resolved: hide an empty folder unless the user opened it
                    if kids.isEmpty && !open { continue }
                    out.append(row(e, depth: depth, kind: .folder, isOpen: open))
                    if open {
                        if kids.isEmpty { out.append(emptyRow(parent: e.url, depth: depth + 1)) }
                        else { walk(e.url, depth: depth + 1, into: &out) }
                    }
                } else {
                    // peek pending: show optimistically, resolve on enumerate → rebuild
                    ensure(e.url)
                    out.append(row(e, depth: depth, kind: .folder, isOpen: open))
                    if open { walk(e.url, depth: depth + 1, into: &out) }
                }
            } else {
                out.append(row(e, depth: depth, kind: .file, isOpen: false))
            }
        }
    }

    private func row(_ e: TreeEntry, depth: Int, kind: TreeRow.Kind, isOpen: Bool) -> TreeRow {
        TreeRow(id: key(e.url), url: e.url, name: e.name, depth: depth, kind: kind, isOpen: isOpen)
    }
    private func emptyRow(parent: URL, depth: Int) -> TreeRow {
        TreeRow(id: "empty:" + key(parent), url: parent, name: "empty", depth: depth, kind: .empty, isOpen: false)
    }

    // MARK: - Filter (async, cancellable, scans deeper than the lazy default)

    private func onFilterChanged() {
        filterTask?.cancel()
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            isFiltering = false
            rebuildRows()                       // restore the prior (persisted) expansion
            return
        }
        isFiltering = true
        guard let root else { return }
        let cap = maxFilterResults
        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            let flat = Self.scan(root: root, query: q, cap: cap)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in self?.applyFilterResults(flat, query: q, root: root) }
        }
    }

    private func applyFilterResults(_ flat: [TreeRow], query q: String, root: URL) {
        guard isFiltering, filter.trimmingCharacters(in: .whitespaces) == q else { return }
        rows = flat.isEmpty
            ? [TreeRow(id: "nomatch", url: root, name: q, depth: 0, kind: .noMatch, isOpen: false)]
            : flat
        clampFocus()
    }

    /// Recursive match scan off the main thread. Includes a folder (open) when any
    /// descendant file matches; includes matching files. Cancellable + capped.
    private static func scan(root: URL, query: String, cap: Int) -> [TreeRow] {
        func walk(_ dir: URL, depth: Int, into out: inout [TreeRow]) {
            if Task.isCancelled || out.count >= cap { return }
            for e in TreeCore.children(of: dir) {
                if Task.isCancelled || out.count >= cap { return }
                if e.isDir {
                    var sub: [TreeRow] = []
                    walk(e.url, depth: depth + 1, into: &sub)
                    if !sub.isEmpty {
                        out.append(TreeRow(id: e.url.standardizedFileURL.path, url: e.url, name: e.name, depth: depth, kind: .folder, isOpen: true))
                        out.append(contentsOf: sub)
                    }
                } else if TreeCore.matches(name: e.name, query: query) {
                    out.append(TreeRow(id: e.url.standardizedFileURL.path, url: e.url, name: e.name, depth: depth, kind: .file, isOpen: false))
                }
            }
        }
        var out: [TreeRow] = []
        walk(root, depth: 0, into: &out)
        return out
    }

    // MARK: - Watching

    private func handleFSEvents(_ dirs: Set<URL>) {
        guard let root else { return }
        let rootKey = key(root)
        var touched = false
        for d in dirs {
            let k = key(d)
            guard k.hasPrefix(rootKey) else { continue }
            if childrenCache[k] != nil {            // we had it cached → re-read that folder
                childrenCache[k] = nil
                ensure(d)
                touched = true
            }
        }
        if touched && !isFiltering { rebuildRows() }
        if isFiltering { onFilterChanged() }        // re-run the active filter
    }

    // MARK: - Keyboard navigation (operates on the flattened `rows`)

    private var navigableRows: [TreeRow] { rows.filter { $0.kind == .file || $0.kind == .folder } }

    func focusFirstIfNeeded() { if focusedID == nil { focusedID = navigableRows.first?.id } }
    func moveFocus(_ delta: Int) {
        let nav = navigableRows
        guard !nav.isEmpty else { return }
        let idx = nav.firstIndex { $0.id == focusedID } ?? -1
        let next = max(0, min(nav.count - 1, idx + delta))
        focusedID = nav[next].id
        if let id = focusedID { requestScroll(to: id) }
    }
    /// → : expand a collapsed folder, or descend into an open one.
    func expandOrDescend() {
        guard let r = focusedRow, r.kind == .folder else { return }
        if r.isOpen { moveFocus(1) } else { toggle(r.url) }
    }
    /// ← : collapse an open folder, or ascend to the parent.
    func collapseOrAscend() {
        guard let r = focusedRow else { return }
        if r.kind == .folder, r.isOpen { toggle(r.url); return }
        let nav = navigableRows
        guard let idx = nav.firstIndex(where: { $0.id == r.id }) else { return }
        for i in stride(from: idx - 1, through: 0, by: -1) where nav[i].depth < r.depth {
            focusedID = nav[i].id; requestScroll(to: nav[i].id); return
        }
    }
    /// Type-ahead: focus the next row whose name has `prefix`.
    func typeAhead(_ prefix: String) {
        let p = prefix.lowercased()
        let nav = navigableRows
        guard !nav.isEmpty else { return }
        let start = (nav.firstIndex { $0.id == focusedID }.map { $0 + 1 }) ?? 0
        let order = Array(nav[start...]) + Array(nav[..<start])
        if let hit = order.first(where: { $0.name.lowercased().hasPrefix(p) }) {
            focusedID = hit.id; requestScroll(to: hit.id)
        }
    }
    var focusedRow: TreeRow? { rows.first { $0.id == focusedID } }
    private func clampFocus() {
        if let f = focusedID, !rows.contains(where: { $0.id == f }) { focusedID = nil }
    }

    // MARK: - Persistence (scoped per watched root)

    private func expandedKey(_ root: URL) -> String { "treeExpanded::" + key(root) }
    private func scrollKey(_ root: URL) -> String { "treeScrollTop::" + key(root) }

    private func loadExpanded(for root: URL) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: expandedKey(root)) ?? [])
    }
    private func saveExpanded() {
        guard let root else { return }
        UserDefaults.standard.set(Array(expanded), forKey: expandedKey(root))
    }
    var persistedTopRowID: String? {
        get { root.flatMap { UserDefaults.standard.string(forKey: scrollKey($0)) } }
        set { if let root, let v = newValue { UserDefaults.standard.set(v, forKey: scrollKey(root)) } }
    }
}
