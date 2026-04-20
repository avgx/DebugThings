import Foundation
import Logging

// MARK: - Custom Format Log Handler
public struct CustomFormatLogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .debug
    
    private let label: String
    private let streams: [TextOutputStream]
    private let dateFormatter: DateFormatter
    
    public init(label: String, streams: [TextOutputStream] = [StdoutOutputStream()]) {
        self.label = label
        self.streams = streams
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    
    public func log(level: Logger.Level, message: Logger.Message,
                    metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let mergedMetadata = self.metadata.merging(metadata ?? [:]) { $1 }
        let metadataOutput = mergedMetadata.isEmpty ? "" : " " + mergedMetadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)][\(label)][\(level)]\(metadataOutput) \(message)\n"
        
        for var stream in streams {
            stream.write(formattedMessage)
        }
    }
}

// MARK: - Stdout Stream
public struct StdoutOutputStream: TextOutputStream {
    public init() {}
    public mutating func write(_ string: String) {
        print(string, terminator: "")
    }
}
