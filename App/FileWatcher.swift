import Foundation

/// Watches a single file (or folder) with a kqueue-backed
/// `DispatchSourceFileSystemObject`. Handles the replace-on-save pattern used by
/// most editors (write to temp, then rename over the original): on rename/delete
/// the original fd goes stale, so we cancel, re-open the path, and re-arm — then
/// still fire `onChange` so the open tab / sidebar re-reads.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.tirthajyoti.Reader.filewatcher")

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit { stop() }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func arm() {
        stop()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib, .link],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let flags = source.data
            let replaced = flags.contains(.rename) || flags.contains(.delete) || flags.contains(.link)

            if replaced {
                // Atomic save replaced the inode — re-arm on the path shortly so
                // the new file exists, then notify.
                self.queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.arm() }
            }
            DispatchQueue.main.async { self.onChange() }
        }

        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source = src
        src.resume()
    }
}
