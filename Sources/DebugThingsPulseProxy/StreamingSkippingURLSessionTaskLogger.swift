import Foundation
import DebugThings

/// Detects long-lived HTTP streams (SSE, MJPEG-style multipart) from response metadata.
public enum URLSessionTaskLoggerStreamingDetection: Sendable {
    /// Returns `true` when the response looks like Server-Sent Events or multipart MJPEG.
    ///
    /// - Note: The first `URLSessionDataDelegate` callback may arrive before a response is available; callers may
    ///   forward that chunk before streaming is detected. Prefer ``PulseNetworkCaptureSettings/excludedURLs`` /
    ///   ``PulseNetworkCaptureSettings/excludedHosts`` for endpoints known to stream indefinitely.
    public static func responseIndicatesSSEOrMJPEG(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        let header = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let mime = (http.mimeType ?? "").lowercased()
        if header.contains("text/event-stream") || mime.contains("text/event-stream") { return true }
        if header.contains("multipart/x-mixed-replace") || mime.contains("multipart/x-mixed-replace") { return true }
        return false
    }
}

/// Skips ``logDataTask(_:didReceive:)`` on the inner logger once a streaming response is recognized.
///
/// Wrap a ``PulseSessionEventLogger`` (or any ``URLSessionTaskLogger``) to avoid sending unbounded bodies to Pulse for
/// SSE/MJPEG while still forwarding task lifecycle events.
public final class StreamingSkippingURLSessionTaskLogger: URLSessionTaskLogger, @unchecked Sendable {
    private let inner: URLSessionTaskLogger
    private let lock = NSLock()
    private var streamingTaskIDs: Set<Int> = []

    public init(inner: URLSessionTaskLogger) {
        self.inner = inner
    }

    public func logTaskCreated(_ task: URLSessionTask) {
        inner.logTaskCreated(task)
    }

    public func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        streamingTaskIDs.remove(task.taskIdentifier)
        lock.unlock()
        inner.logTask(task, didCompleteWithError: error)
    }

    public func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        inner.logTask(task, didFinishCollecting: metrics)
    }

    public func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {
        inner.logTask(task, didFinishDecodingWithError: error)
    }

    public func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if URLSessionTaskLoggerStreamingDetection.responseIndicatesSSEOrMJPEG(dataTask.response) {
            streamingTaskIDs.insert(dataTask.taskIdentifier)
        }
        let skipBody = streamingTaskIDs.contains(dataTask.taskIdentifier)
        lock.unlock()

        if skipBody { return }
        inner.logDataTask(dataTask, didReceive: data)
    }
}
