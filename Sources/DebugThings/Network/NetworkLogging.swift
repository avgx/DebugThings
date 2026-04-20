import Foundation

/// Hooks for logging around convenience APIs such as `URLSession` async `data(for:)` wrappers.
///
/// This is separate from ``URLSessionTaskLogger``, which is tailored to delegate-based session flows and tools like
/// ``NetworkLoggingDelegate``.
public protocol NetworkLogging {
    func logRequest(_ request: URLRequest, data: Data?, response: URLResponse?, error: Error?)
    func logResponse(_ response: URLResponse, data: Data, duration: TimeInterval)
    func logError(_ error: Error, for request: URLRequest)
}
