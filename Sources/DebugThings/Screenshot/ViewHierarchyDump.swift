#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
import UIKit

/// Text dump of connected window scenes / view controllers / views for screenshot diagnostics.
@MainActor
public enum ViewHierarchyDump {
    public static func capture() -> String {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                lhs.session.persistentIdentifier < rhs.session.persistentIdentifier
            }

        guard !scenes.isEmpty else {
            return "No UIWindowScene"
        }

        var lines: [String] = []
        for scene in scenes {
            let activation = String(describing: scene.activationState)
            lines.append("Scene \(scene.session.persistentIdentifier) activation=\(activation)")
            let windows = scene.windows.sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
                return ObjectIdentifier(lhs) < ObjectIdentifier(rhs)
            }
            for window in windows {
                lines.append(
                    "  Window key=\(window.isKeyWindow) hidden=\(window.isHidden) level=\(window.windowLevel.rawValue) \(typeName(window))"
                )
                if let root = window.rootViewController {
                    lines.append(contentsOf: describe(viewController: root, depth: 2))
                } else {
                    lines.append(indent(2) + "rootViewController=nil")
                }
                lines.append(contentsOf: describe(view: window, depth: 2, maxDepth: 6))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(viewController: UIViewController, depth: Int) -> [String] {
        var lines: [String] = []
        let title = viewController.title.map { "\"\($0)\"" } ?? "nil"
        let navTitle = viewController.navigationItem.title.map { "\"\($0)\"" }
        var extras = "title=\(title)"
        if let navTitle, navTitle != title {
            extras += " navTitle=\(navTitle)"
        }
        if let tab = viewController.tabBarItem.title {
            extras += " tab=\"\(tab)\""
        }
        lines.append("\(indent(depth))VC \(typeName(viewController)) \(extras)")

        if let nav = viewController as? UINavigationController {
            lines.append("\(indent(depth + 1))stack(\(nav.viewControllers.count)):")
            for child in nav.viewControllers {
                lines.append(contentsOf: describe(viewController: child, depth: depth + 2))
            }
            if let visible = nav.visibleViewController,
               visible !== nav.viewControllers.last {
                lines.append("\(indent(depth + 1))visible:")
                lines.append(contentsOf: describe(viewController: visible, depth: depth + 2))
            }
        } else if let tab = viewController as? UITabBarController {
            let selectedIndex = tab.selectedIndex
            lines.append("\(indent(depth + 1))selectedIndex=\(selectedIndex)")
            for (index, child) in (tab.viewControllers ?? []).enumerated() {
                let marker = index == selectedIndex ? "*" : " "
                lines.append("\(indent(depth + 1))[\(marker)\(index)]")
                lines.append(contentsOf: describe(viewController: child, depth: depth + 2))
            }
        } else if let split = viewController as? UISplitViewController {
            lines.append("\(indent(depth + 1))split columns=\(split.viewControllers.count)")
            for child in split.viewControllers {
                lines.append(contentsOf: describe(viewController: child, depth: depth + 2))
            }
        } else {
            for child in viewController.children {
                lines.append(contentsOf: describe(viewController: child, depth: depth + 1))
            }
        }

        if let presented = viewController.presentedViewController {
            lines.append("\(indent(depth + 1))presented:")
            lines.append(contentsOf: describe(viewController: presented, depth: depth + 2))
        }

        return lines
    }

    private static func describe(view: UIView, depth: Int, maxDepth: Int) -> [String] {
        guard depth <= maxDepth else { return [] }
        var lines: [String] = []
        let frame = view.frame
        let frameText = String(
            format: "%.0f,%.0f %.0fx%.0f",
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height
        )
        var extras = "frame=(\(frameText))"
        if view.isHidden { extras += " hidden" }
        if view.alpha < 0.01 { extras += " alpha=0" }
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            extras += " text=\"\(text.prefix(40))\""
        }
        lines.append("\(indent(depth))View \(typeName(view)) \(extras)")

        let children = view.subviews.filter { !$0.isHidden && $0.alpha > 0.01 }
        for child in children.prefix(24) {
            lines.append(contentsOf: describe(view: child, depth: depth + 1, maxDepth: maxDepth))
        }
        if children.count > 24 {
            lines.append("\(indent(depth + 1))… +\(children.count - 24) more subviews")
        }
        return lines
    }

    private static func typeName(_ object: Any) -> String {
        String(describing: type(of: object))
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
    }
}
#endif
