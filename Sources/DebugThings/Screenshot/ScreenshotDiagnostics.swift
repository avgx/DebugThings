import Foundation

/// Registry of diagnostic string providers captured when the user takes a screenshot.
///
/// Register providers from feature screens (for example an open camera view). Providers are
/// invoked on the main actor when ``ScreenshotObserver`` handles a screenshot.
@MainActor
public enum ScreenshotDiagnostics {
    private static var providers: [String: () -> String] = [:]

    /// Registers or replaces a named diagnostics provider.
    public static func register(id: String, provider: @escaping () -> String) {
        providers[id] = provider
    }

    /// Removes a previously registered provider.
    public static func unregister(id: String) {
        providers.removeValue(forKey: id)
    }

    /// Captures all registered providers in stable id order.
    ///
    /// Returns an empty string when nothing is registered.
    public static func captureAll() -> String {
        let ids = providers.keys.sorted()
        guard !ids.isEmpty else { return "" }

        var sections: [String] = []
        for id in ids {
            guard let provider = providers[id] else { continue }
            let body = provider()
            if body.isEmpty {
                sections.append("[\(id)] (empty)")
            } else {
                sections.append("[\(id)]\n\(body)")
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
