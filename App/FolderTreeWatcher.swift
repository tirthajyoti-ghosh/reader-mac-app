import Foundation
import CoreServices

/// Watches a whole folder subtree with a SINGLE recursive, coalesced `FSEventStream`
/// (not one kqueue FD per folder — that exhausts descriptors and doesn't fit a tree).
/// Reports the set of changed directory URLs (a file event maps to its parent dir),
/// coalesced with a short latency so editor save-storms fire once. The tree store
/// invalidates just those folders' caches and refreshes the expanded ones.
final class FolderTreeWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: (Set<URL>) -> Void
    private let queue = DispatchQueue(label: "com.tirthajyoti.Reader.treewatch")

    init(root: URL, onChange: @escaping (Set<URL>) -> Void) {
        self.onChange = onChange
        start(root: root)
    }
    deinit { stop() }

    private func start(root: URL) {
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            treeWatcherCallback,
            &ctx,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,                               // coalesce bursts over 300ms
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    fileprivate func deliver(paths: [String]) {
        var dirs = Set<URL>()
        for p in paths {
            let u = URL(fileURLWithPath: p)
            dirs.insert(u)                        // the path itself (may be a dir)
            dirs.insert(u.deletingLastPathComponent())   // and its parent (file → its folder)
        }
        DispatchQueue.main.async { [onChange] in onChange(dirs) }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Top-level (non-capturing) C callback — required by FSEvents. Recovers the watcher
/// from the context `info` pointer and forwards the changed paths.
private func treeWatcherCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderTreeWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]) ?? []
    watcher.deliver(paths: paths)
}
