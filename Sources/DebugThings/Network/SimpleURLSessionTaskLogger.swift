import Foundation
import Logging

public struct SimpleURLSessionTaskLogger: URLSessionTaskLogger {
    private let logger: Logger
    
    public init(label: String = "network") {
        self.logger = Logger(label: label)
    }
    
    public func logTaskCreated(_ task: URLSessionTask) {
        logger.debug("→ Task created: \(task.taskIdentifier) \(task.originalRequest?.url?.absoluteString ?? "?")")
    }
    
    public func logTask(_ task: URLSessionTask, didUpdateProgress progress: (completed: Int64, total: Int64)) {
        let percentage = progress.total > 0 ? Int(Double(progress.completed) / Double(progress.total) * 100) : 0
        logger.debug("↻ Progress: \(percentage)% (\(progress.completed)/\(progress.total))")
    }
    
    public func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.error("✗ Task failed: \(task.taskIdentifier) - \(error.localizedDescription)")
        } else {
            logger.debug("✓ Task completed: \(task.taskIdentifier)")
        }
    }
    
    public func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {
        if let error = error {
            logger.error("✗ Task failedDecoding: \(task.taskIdentifier) - \(error.localizedDescription)")
        } else {
            logger.debug("✓ Task completedDecoding: \(task.taskIdentifier)")
        }
    }
    
    public func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let duration = metrics.taskInterval.duration
        logger.debug("⏱ Duration: \(String(format: "%.2f", duration * 1000))ms")
    }
    
    public func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {
        logger.debug("📦 Received \(data.count) bytes")
    }
}
