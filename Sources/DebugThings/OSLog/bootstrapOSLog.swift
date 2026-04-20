import Foundation
import Logging
import OSLog

extension DebugThings {

    /// Installs SwiftLog with ``OSLogHandler`` as the only backend.
    public static func bootstrapOSLog(
        level: Logging.Logger.Level = .trace,
        metadata: Logging.Logger.Metadata? = nil,
        subsystem: String? = Bundle.main.bundleIdentifier
    ) {

        guard LoggingBootstrap.claimSwiftLogInstall() else { return }

        LoggingSystem.bootstrap { label in
            let osLogger = os.Logger(subsystem: subsystem ?? "default", category: label)

            var handler = OSLogHandler(logger: osLogger)
            handler.logLevel = level
            if let metadata {
                handler.metadata = metadata
            }
            return handler
        }
    }
}
