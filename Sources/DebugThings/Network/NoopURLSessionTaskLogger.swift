import Foundation

public struct NoopURLSessionTaskLogger: URLSessionTaskLogger {
    public func logTaskCreated(_ task: URLSessionTask) {}
    public func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {}
    public func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {}
    public func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {}
    public func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {}
    
    public init() {}
}
