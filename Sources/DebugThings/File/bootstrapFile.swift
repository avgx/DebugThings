import Foundation
import Logging
import OSLog

extension DebugThings {

    /// Installs SwiftLog with a ``FileLogHandler`` plus ``OSLogHandler`` for on-device visibility.
    ///
    /// - Parameters:
    ///   - level: Minimum level written to both backends.
    ///   - logFileURL: Destination file; parent directories are created if needed.
    ///   - metadata: Optional default metadata applied to every handler in the multiplex.
    ///   - subsystem: OSLog subsystem; defaults to ``Bundle/main`` bundle identifier when available.
    public static func bootstrapFile(
        level: Logging.Logger.Level = .info,
        logFileURL: URL,
        metadata: Logging.Logger.Metadata? = nil,
        subsystem: String? = Bundle.main.bundleIdentifier
    ) {

        guard LoggingBootstrap.claimSwiftLogInstall() else { return }

        LoggingSystem.bootstrap { label in
            var handlers: [LogHandler] = []

            if var fileLogHandler = try? FileLogHandler(label: label, logFileURL: logFileURL) {
                fileLogHandler.logLevel = level
                if let metadata {
                    fileLogHandler.metadata = metadata
                }
                handlers.append(fileLogHandler)
            }

            let osLogger = os.Logger(subsystem: subsystem ?? "default", category: label)
            var osLogHandler = OSLogHandler(logger: osLogger)
            osLogHandler.logLevel = level
            if let metadata {
                osLogHandler.metadata = metadata
            }
            handlers.append(osLogHandler)

            return MultiplexLogHandler(handlers)
        }
    }
}
