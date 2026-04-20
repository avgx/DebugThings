import Foundation
import Logging

extension DebugThings {

    /// Installs SwiftLog with a single ``StreamLogHandler/standardOutput(label:)`` backend.
    public static func bootstrapStandardOutput(
        level: Logger.Level = .trace,
        metadata: Logger.Metadata? = nil
    ) {
        guard LoggingBootstrap.claimSwiftLogInstall() else { return }

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = level
            if let metadata {
                handler.metadata = metadata
            }
            return handler
        }
    }
}
