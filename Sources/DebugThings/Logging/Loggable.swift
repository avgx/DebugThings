import Foundation
import Logging

/// Associates a SwiftLog ``Logger`` with a type via a stable subsystem label.
///
/// Log through ``Logger`` directly (for example ``Logger/debug(_:metadata:file:function:line:)``). SwiftLog already
/// uses `@autoclosure` for message and metadata, so expensive string work is skipped when the level is disabled.
public protocol Loggable {
    /// Shared SwiftLog logger for this type.
    static var logger: Logger { get }
    /// Subsystem string used as the logger label.
    static var subsystem: String { get }
}

public extension Loggable {
    static var logger: Logger {
        Logger(label: subsystem)
    }

    static var subsystem: String {
        String(describing: Self.self).lowercased()
    }

    /// Instance convenience for the conforming type's ``logger``.
    var logger: Logger {
        Self.logger
    }
}
