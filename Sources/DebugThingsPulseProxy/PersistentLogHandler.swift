// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Pulse
import Logging

/// A ``LogHandler`` that persists SwiftLog entries into a Pulse ``LoggerStore``.
///
/// ```swift
/// import Logging
/// import DebugThingsPulseProxy
///
/// LoggingSystem.bootstrap(PersistentLogHandler.init)
/// let logger = Logger(label: "com.example.app")
/// logger.info("Stored in LoggerStore")
/// ```
public struct PersistentLogHandler {
    public var metadata = Logger.Metadata()
    public var logLevel = Logger.Level.info
    public var metadataProvider: Logger.MetadataProvider?

    private let store: LoggerStore
    private let label: String

    public init(label: String) {
        self.init(label: label, store: .shared)
    }

    public init(label: String, store: LoggerStore) {
        self.init(label: label, metadataProvider: nil, store: store)
    }
    
    public init(label: String, metadataProvider: Logger.MetadataProvider?) {
        self.init(label: label, metadataProvider: metadataProvider, store: .shared)
    }
    
    public init(label: String, metadataProvider: Logger.MetadataProvider?, store: LoggerStore) {
        self.label = label
        self.metadataProvider = metadataProvider
        self.store = store
    }
}

extension PersistentLogHandler: LogHandler {
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        } set(newValue) {
            metadata[key] = newValue
        }
    }

    public func log(event: LogEvent) {
        store.storeMessage(
            label: label,
            level: .init(event.level),
            message: event.message.description,
            metadata: .init(mergedMetadata(with: event.metadata)),
            file: event.file,
            function: event.function,
            line: event.line
        )
    }
    
    /// Merges metadata from a log entry metadata with the metadata set on this logger and any metadata
    /// returned from the metadata provider, if present.
    ///
    /// When multiple sources of metadata return values for the same key, the more specific value will win,
    /// i.e. the priority from least to most specific is: the metadata provider, the handler's metadata, then
    /// finally the log entry's metadata.
    ///
    private func mergedMetadata(with metadata: Logger.Metadata?) -> Logger.Metadata {
        return (metadata ?? [:])
            .merging(self.metadata, uniquingKeysWith: { (current, _) in current })
            .merging(self.metadataProvider?.get() ?? [:], uniquingKeysWith: { (current, _) in current })
    }
}

// MARK: - Private (Logger.Level <-> LoggerStore.Level)

private extension LoggerStore.Level {
    init(_ level: Logger.Level) {
        switch level {
        case .trace: self = .trace
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
}

// MARK: - Private (Logger.Metadata <-> LoggerStore.Metadata)

private extension LoggerStore.Metadata {
    init(_ metadata: Logger.Metadata) {
        self = metadata.compactMapValues(LoggerStore.MetadataValue.init)
    }
}

private extension LoggerStore.MetadataValue {
    init?(_ value: Logger.MetadataValue) {
        switch value {
        case .string(let value): self = .string(value)
        case .stringConvertible(let value): self = .stringConvertible(value)
        case .dictionary: return nil // Unsupported
        case .array: return nil // Unsupported
        }
    }
}
