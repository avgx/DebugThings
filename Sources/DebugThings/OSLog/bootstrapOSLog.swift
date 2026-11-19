import Foundation
import Logging
import OSLogHandler

extension DebugThings {

    /// Installs SwiftLog with the `swift-log-oslog` ``OSLogHandler`` as the only backend.
    ///
    /// Metadata follows that handler's deny-by-default privacy: values tagged `Sensitivity.public` stay
    /// visible, and every other value is `privacy: .private`. The message stays public.
    ///
    /// - Parameters:
    ///   - level: Fixed SwiftLog threshold. `nil` leaves the handler's level unset, so it follows the
    ///     system's per-category enablement.
    ///   - metadata: Optional metadata applied to every handler. Untagged values are private in Console.
    ///   - subsystem: OSLog subsystem. Defaults to ``Bundle/main``'s identifier, then `"default"`.
    public static func bootstrapOSLog(
        level: Logging.Logger.Level? = nil,
        metadata: Logging.Logger.Metadata? = nil,
        subsystem: String? = Bundle.main.bundleIdentifier
    ) {

        guard LoggingBootstrap.claimSwiftLogInstall() else { return }

        let resolvedSubsystem = subsystem ?? "default"

        LoggingSystem.bootstrap { label in
            var handler = OSLogHandler(subsystem: resolvedSubsystem, category: label)
            if let level {
                handler.logLevel = level
            }
            if let metadata {
                handler.metadata = metadata
            }
            return handler
        }
    }
}
