import Foundation

/// Coordinates a single ``LoggingSystem/bootstrap`` install per process across all `DebugThings` modules.
///
/// Call ``claimSwiftLogInstall()`` before ``LoggingSystem/bootstrap``. The first caller receives `true`;
/// later callers receive `false` and should skip bootstrapping (mirrors prior `DebugThings.configured` behavior).
package enum LoggingBootstrap {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var didInstallSwiftLogBackend = false

    /// Returns `true` only the first time in a process, then `false`.
    ///
    /// - Important: Call ``LoggingSystem/bootstrap`` in the same code path when this returns `true`, otherwise
    ///   subsequent bootstraps are permanently skipped.
    package static func claimSwiftLogInstall() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didInstallSwiftLogBackend { return false }
        didInstallSwiftLogBackend = true
        return true
    }
}
