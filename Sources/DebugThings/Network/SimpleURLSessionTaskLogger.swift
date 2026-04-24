import Foundation
import Logging

public struct SimpleURLSessionTaskLogger: URLSessionTaskLogger {
    private let logger: Logger
    private let logReceiveData: Bool
    
    public init(label: String = "network", logReceiveData: Bool = false) {
        self.logger = Logger(label: label)
        self.logReceiveData = logReceiveData
    }
    
    public func logTaskCreated(_ task: URLSessionTask) {
        logger.debug("→ Task created: \(task.taskIdentifier) \(task.originalRequest?.url?.absoluteString ?? "?")")
    }
    
    public func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if error.isCancellation() {
                logger.debug("✓ Task \(task.taskIdentifier) cancelled")
            } else {
                logger.error("✗ Task \(task.taskIdentifier) failed: \(error.localizedDescription)")
            }
        } else {
            logger.debug("✓ Task \(task.taskIdentifier) completed")
        }
    }
    
    public func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {
        if let error = error {
            logger.error("✗ Task \(task.taskIdentifier) failedDecoding: \(error.localizedDescription)")
        } else {
            logger.debug("✓ Task \(task.taskIdentifier) completedDecoding")
        }
    }
    
    public func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let duration = metrics.taskInterval.duration
        logger.debug("Task \(task.taskIdentifier) duration: \(String(format: "%.2f", duration * 1000))ms")
    }
    
    public func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {
        if logReceiveData {
            logger.debug("Task \(dataTask.taskIdentifier) Received \(data.count) bytes")
        }
    }
}
