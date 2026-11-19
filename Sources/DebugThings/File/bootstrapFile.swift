import Foundation
import Logging
import OSLogHandler

extension DebugThings {

    /// Installs SwiftLog with a file handler plus ``OSLogHandler`` for on-device visibility.
    ///
    /// The file handler is a ``FileLogHandler`` by default. When `maxFileBytes` is set, it is a
    /// ``RollingFileLogHandler`` that keeps the file under that size, with one backup at `<logFileURL>.1`.
    ///
    /// - Parameters:
    ///   - level: Minimum level written to both backends.
    ///   - logFileURL: Destination file; parent directories are created if needed.
    ///   - metadata: Optional default metadata applied to every handler in the multiplex.
    ///   - subsystem: OSLog subsystem; defaults to ``Bundle/main`` bundle identifier when available.
    ///   - maxFileBytes: When non-nil, rotate the file once it would exceed this size. `nil` disables rotation.
    public static func bootstrapFile(
        level: Logging.Logger.Level = .info,
        logFileURL: URL,
        metadata: Logging.Logger.Metadata? = nil,
        subsystem: String? = Bundle.main.bundleIdentifier,
        maxFileBytes: Int? = nil
    ) {

        guard LoggingBootstrap.claimSwiftLogInstall() else { return }

        LoggingSystem.bootstrap { label in
            var handlers: [LogHandler] = []

            if let maxFileBytes {
                if var rollingHandler = try? RollingFileLogHandler(
                    label: label,
                    logFileURL: logFileURL,
                    maxFileBytes: maxFileBytes
                ) {
                    rollingHandler.logLevel = level
                    if let metadata {
                        rollingHandler.metadata = metadata
                    }
                    handlers.append(rollingHandler)
                }
            } else if var fileLogHandler = try? FileLogHandler(label: label, logFileURL: logFileURL) {
                fileLogHandler.logLevel = level
                if let metadata {
                    fileLogHandler.metadata = metadata
                }
                handlers.append(fileLogHandler)
            }

            var osLogHandler = OSLogHandler(
                subsystem: subsystem ?? "default",
                category: label
            )
            osLogHandler.logLevel = level
            if let metadata {
                osLogHandler.metadata = metadata
            }
            handlers.append(osLogHandler)

            return MultiplexLogHandler(handlers)
        }
    }
}
