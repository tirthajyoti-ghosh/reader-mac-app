import Foundation
import os

/// Lightweight perf logging for the document-open path. Everything goes through the
/// unified log so it can be read live, without a window or focus, via:
///
///     log stream --predicate 'subsystem == "com.tirthajyoti.Reader"' --style compact
///
/// Use `Perf.now()` to stamp a start and `Perf.done(_:since:_:)` to log an elapsed
/// milliseconds delta; `Perf.event(_:_:)` logs a bare milestone.
enum Perf {
    static let log = Logger(subsystem: "com.tirthajyoti.Reader", category: "perf")

    @inline(__always) static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    static func event(_ name: String, _ detail: String = "") {
        log.info("\(name, privacy: .public) \(detail, privacy: .public)")
    }

    static func done(_ name: String, since t0: CFAbsoluteTime, _ detail: String = "") {
        let msStr = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        log.info("\(name, privacy: .public) \(msStr, privacy: .public)ms \(detail, privacy: .public)")
    }
}
