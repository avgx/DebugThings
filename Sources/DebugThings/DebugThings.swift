import Foundation

/// Namespace for logging bootstrap helpers built on [SwiftLog](https://github.com/apple/swift-log).
public enum DebugThings {}

extension Thread {
    /// Prints the current thread's call stack to standard output.
    public static func stackTrace() {
        Thread.callStackSymbols.forEach { print($0) }
    }
}

extension Error {
    public func isCancellation() -> Bool {
        if self is CancellationError { return true }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
