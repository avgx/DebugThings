#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
import Foundation
import UIKit
import Logging

/// Observes device screenshots and logs registered diagnostics plus the UIKit hierarchy.
@MainActor
public enum ScreenshotObserver: Loggable {
    /// Most recent screenshot capture. Useful for future “Report a bug”.
    public private(set) static var lastCapture: Capture?

    private static var observer: NSObjectProtocol?

    public struct Capture: Sendable {
        public let takenAt: Date
        public let diagnostics: String
        public let hierarchy: String
    }

    public static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handleScreenshot()
            }
        }
    }

    /// Safe to call from app bootstrap (may not be on the main actor yet).
    nonisolated public static func startFromBootstrap() {
        Task { @MainActor in
            start()
        }
    }

    public static func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private static func handleScreenshot() {
        let takenAt = Date()
        let diagnostics = ScreenshotDiagnostics.captureAll()
        let hierarchy = ViewHierarchyDump.capture()
        lastCapture = Capture(takenAt: takenAt, diagnostics: diagnostics, hierarchy: hierarchy)

        let timestamp = Self.formattedTimestamp(takenAt)
        if diagnostics.isEmpty {
            logger.info(
                """
                Screenshot taken at \(timestamp)
                UIKit hierarchy:
                \(hierarchy)
                """
            )
        } else {
            logger.info(
                """
                Screenshot taken at \(timestamp)
                Diagnostics:
                \(diagnostics)
                UIKit hierarchy:
                \(hierarchy)
                """
            )
        }
    }

    private static func formattedTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
#endif
