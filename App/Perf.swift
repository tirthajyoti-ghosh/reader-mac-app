import Foundation
import os

/// Lightweight perf logging for the document-open path. Goes to the unified log
/// (read live with `log stream --predicate 'subsystem == "com.tirthajyoti.Reader"'`)
/// AND, when the env var `READER_PERF_FILE` is set, appends each event to that file
/// — so a measurement harness that can't read the unified log can still collect the
/// numbers. Use `Perf.now()` + `Perf.done(_:since:_:)` for elapsed ms, `event` for a
/// bare milestone.
enum Perf {
    static let log = Logger(subsystem: "com.tirthajyoti.Reader", category: "perf")
    private static let fileURL: URL? =
        ProcessInfo.processInfo.environment["READER_PERF_FILE"].map { URL(fileURLWithPath: $0) }
    private static let fileQueue = DispatchQueue(label: "com.tirthajyoti.Reader.perf.file")

    @inline(__always) static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    static func event(_ name: String, _ detail: String = "") {
        log.notice("\(name, privacy: .public) \(detail, privacy: .public)")
        sink("\(name) \(detail)")
    }

    static func done(_ name: String, since t0: CFAbsoluteTime, _ detail: String = "") {
        let msStr = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        log.notice("\(name, privacy: .public) \(msStr, privacy: .public)ms \(detail, privacy: .public)")
        sink("\(name) \(msStr)ms \(detail)")
    }

    private static func sink(_ line: String) {
        guard let fileURL else { return }
        let entry = String(format: "%.4f %@\n", CFAbsoluteTimeGetCurrent(), line)
        fileQueue.async {
            guard let data = entry.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)   // first write creates the file
            }
        }
    }
}
