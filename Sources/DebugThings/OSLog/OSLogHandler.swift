import Foundation
import Logging
import OSLog

/// Bridges [SwiftLog](https://github.com/apple/swift-log) to Apple's unified logging (`os.Logger`).
///
/// ## Metadata and privacy
///
/// `swift-log` metadata is serialized into a plain string and logged with **public** visibility so it shows up in
/// Console while debugging. Unified Logging does **not** apply `privacy:` to arbitrary key–value metadata; to redact
/// secrets, build the primary ``Logger/Message`` at the call site using `os.Logger` interpolation with
/// `privacy: .private`, or omit sensitive values from metadata entirely.
public struct OSLogHandler: Logging.LogHandler {
    private let logger: os.Logger
    private var _logLevel: Logging.Logger.Level = .trace
    private var _metadata: Logging.Logger.Metadata = [:]

    public init(logger: os.Logger) {
        self.logger = logger
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { _metadata[key] }
        set { _metadata[key] = newValue }
    }

    public var metadata: Logging.Logger.Metadata {
        get { _metadata }
        set { _metadata = newValue }
    }

    public var logLevel: Logging.Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    public func log(event: Logging.LogEvent) {
        let combinedMetadata = mergeMetadata(self.metadata, event.metadata)
        let metadataSuffix = combinedMetadata.isEmpty
            ? ""
            : " | " + Self.formatMetadataForOSLog(combinedMetadata)

        let osLogType: OSLogType
        switch event.level {
        case .trace, .debug:
            osLogType = .debug
        case .info, .notice:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        case .critical:
            osLogType = .fault
        }

        logger.log(
            level: osLogType,
            "\(event.message.description, privacy: .public)\(metadataSuffix, privacy: .public)"
        )
    }

    private func mergeMetadata(
        _ lhs: Logging.Logger.Metadata,
        _ rhs: Logging.Logger.Metadata?
    ) -> Logging.Logger.Metadata {
        var result = lhs
        if let rhs {
            for (key, value) in rhs {
                result[key] = value
            }
        }
        return result
    }

    private static func formatMetadataForOSLog(_ metadata: Logging.Logger.Metadata) -> String {
        metadata.sorted { $0.key < $1.key }
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: " ")
    }
}
