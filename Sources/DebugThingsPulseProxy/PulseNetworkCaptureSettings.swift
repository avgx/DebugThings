import Foundation
import DebugThings
import Pulse

// Re-export Pulse types commonly used alongside this module.
public typealias NetworkLogger = Pulse.NetworkLogger
public typealias LoggerStore = Pulse.LoggerStore

/// App-driven settings mirrored into ``NetworkLogger/Configuration``.
///
/// ``NetworkLogger`` keeps an immutable configuration per instance. Changing capture rules at runtime (for example
/// from settings UI) is done by assigning a new logger to ``NetworkLogger/shared``, which ``applyToSharedNetworkLogger(store:)`` performs.
public struct PulseNetworkCaptureSettings: Sendable, Equatable {
    public var label: String?
    public var isWaitingForDecoding: Bool
    public var includedHosts: Set<String>
    public var includedURLs: Set<String>
    public var excludedHosts: Set<String>
    public var excludedURLs: Set<String>
    public var sensitiveHeaders: Set<String>
    public var sensitiveQueryItems: Set<String>
    public var sensitiveDataFields: Set<String>
    public var isRegexEnabled: Bool

    public init(
        label: String? = nil,
        isWaitingForDecoding: Bool = false,
        includedHosts: Set<String> = [],
        includedURLs: Set<String> = [],
        excludedHosts: Set<String> = [],
        excludedURLs: Set<String> = [],
        sensitiveHeaders: Set<String> = [],
        sensitiveQueryItems: Set<String> = [],
        sensitiveDataFields: Set<String> = [],
        isRegexEnabled: Bool = false
    ) {
        self.label = label
        self.isWaitingForDecoding = isWaitingForDecoding
        self.includedHosts = includedHosts
        self.includedURLs = includedURLs
        self.excludedHosts = excludedHosts
        self.excludedURLs = excludedURLs
        self.sensitiveHeaders = sensitiveHeaders
        self.sensitiveQueryItems = sensitiveQueryItems
        self.sensitiveDataFields = sensitiveDataFields
        self.isRegexEnabled = isRegexEnabled
    }

    /// Open capture rules (no include filters, no redaction presets).
    public static let `default` = PulseNetworkCaptureSettings()

    /// Reasonable redaction defaults for common auth-related fields.
    public static let sensitive = PulseNetworkCaptureSettings(
        sensitiveHeaders: ["Authorization", "Access-Token", "API-Key"],
        sensitiveQueryItems: ["password", "token", "auth_token", "authToken", "api_key"],
        sensitiveDataFields: ["password", "accessToken", "refreshToken", "secret"]
    )

    /// Builds a ``NetworkLogger/Configuration`` snapshot (useful in tests).
    public func networkLoggerConfiguration() -> NetworkLogger.Configuration {
        var configuration = NetworkLogger.Configuration()
        copyFields(into: &configuration)
        return configuration
    }

    /// Replaces ``NetworkLogger/shared`` with a logger built from these settings.
    ///
    /// Prefer calling from the main actor when updating UI-driven settings.
    public func applyToSharedNetworkLogger(store: LoggerStore? = nil) {
        if let store {
            NetworkLogger.shared = NetworkLogger(store: store) { self.copyFields(into: &$0) }
        } else {
            NetworkLogger.shared = NetworkLogger { self.copyFields(into: &$0) }
        }
    }

    private func copyFields(into configuration: inout NetworkLogger.Configuration) {
        configuration.label = label
        configuration.isWaitingForDecoding = isWaitingForDecoding
        configuration.includedHosts = includedHosts
        configuration.includedURLs = includedURLs
        configuration.excludedHosts = excludedHosts
        configuration.excludedURLs = excludedURLs
        configuration.sensitiveHeaders = sensitiveHeaders
        configuration.sensitiveQueryItems = sensitiveQueryItems
        configuration.sensitiveDataFields = sensitiveDataFields
        configuration.isRegexEnabled = isRegexEnabled
    }
}

/// Forwards URL session events to the **current** ``NetworkLogger/shared`` instance.
///
/// Always reads ``NetworkLogger/shared`` on each callback so runtime reconfiguration via
/// ``PulseNetworkCaptureSettings/applyToSharedNetworkLogger(store:)`` takes effect immediately.
public final class PulseSessionEventLogger: URLSessionTaskLogger, @unchecked Sendable {

    public init() {}

    public func logTaskCreated(_ task: URLSessionTask) {
        NetworkLogger.shared.logTaskCreated(task)
    }

    public func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        NetworkLogger.shared.logTask(task, didCompleteWithError: error)
    }

    public func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        NetworkLogger.shared.logTask(task, didFinishCollecting: metrics)
    }

    public func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {
        NetworkLogger.shared.logTask(task, didFinishDecodingWithError: error)
    }

    public func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {
        NetworkLogger.shared.logDataTask(dataTask, didReceive: data)
    }
}
