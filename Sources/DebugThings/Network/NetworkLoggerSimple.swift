import Foundation
import Logging

public class NetworkLoggerSimple {
    private let logger: Logger
    private let logBody: Bool
    
    public init(logger: Logger = Logger(label: "http"), logBody: Bool = false) {
        self.logger = logger
        self.logBody = logBody
    }
    
    func logRequest(_ request: URLRequest) {
        logger.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            for (key, value) in headers {
                logger.debug("  \(key): \(value)")
            }
        }
        if let body = request.httpBody, logBody {
            let truncated = String(data: body.prefix(500), encoding: .utf8) ?? ""
            logger.debug("  Body: \(truncated)\(body.count > 500 ? "..." : "")")
        }
    }
    
    func logResponse(_ response: HTTPURLResponse, body: Data, url: String) {
        let emoji = response.isSuccessful ? "✓" : "✗"
        logger.debug("← \(emoji) \(response.statusCode)  (\(body.count) bytes) \(url)")
        if !body.isEmpty && logBody {
            let truncated = String(data: body.prefix(500), encoding: .utf8) ?? ""
            logger.debug("  Body: \(truncated)\(body.count > 500 ? "..." : "")")
        }
    }
    
    func logError(_ error: Error, url: String) {
        logger.error("✗ Error for \(url): \(error.localizedDescription)")
    }
}

extension HTTPURLResponse {
    var isSuccessful: Bool {
        200..<300 ~= statusCode
    }
}
