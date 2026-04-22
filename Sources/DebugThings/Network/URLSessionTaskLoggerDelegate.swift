import Foundation
import Logging

// MARK: - Network Logging Delegate

/// Forwards `URLSession` delegate callbacks to a ``URLSessionTaskLogger`` (SwiftLog, Pulse, or a custom wrapper).
public final class URLSessionTaskLoggerDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate,
    @unchecked Sendable
{
    private let taskLogger: URLSessionTaskLogger
    private var taskStartTimes: [Int: Date] = [:]
    private var taskData: [Int: Data] = [:]
    
    public init(taskLogger: URLSessionTaskLogger) {
        self.taskLogger = taskLogger
        super.init()
    }
    
    // MARK: URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        taskStartTimes[task.taskIdentifier] = Date()
        taskLogger.logTaskCreated(task)
    }
        
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        taskLogger.logTask(task, didCompleteWithError: error)
        taskStartTimes.removeValue(forKey: task.taskIdentifier)
        taskData.removeValue(forKey: task.taskIdentifier)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        taskLogger.logTask(task, didFinishCollecting: metrics)
    }
    
    // MARK: URLSessionDataDelegate
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        taskLogger.logDataTask(dataTask, didReceive: data)
        
        if var existingData = taskData[dataTask.taskIdentifier] {
            existingData.append(data)
            taskData[dataTask.taskIdentifier] = existingData
        } else {
            taskData[dataTask.taskIdentifier] = data
        }
    }
}
