import Foundation

/// Hooks for logging URL session work from delegate callbacks (`URLSessionTaskDelegate`, `URLSessionDataDelegate`, …).
///
/// Implementations include ``SimpleURLSessionTaskLogger`` (SwiftLog) and, in ``DebugThingsPulseProxy``,
/// ``PulseSessionEventLogger`` plus ``StreamingSkippingURLSessionTaskLogger``.
public protocol URLSessionTaskLogger: Sendable {
    func logTaskCreated(_ task: URLSessionTask)
    func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?)
    func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
    func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?)
    func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data)
}
