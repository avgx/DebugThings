import Foundation

/// Renders crash models as plain text for logs, mail bodies, or text views.
///
/// **What:** Formats `AnalyzedCrash` (preferred) or raw `DecodedCrash` into a monospaced report.
/// **Why:** Presentation stays outside `CrashAnalyzer` so JSON/UI layers can reuse the same models.
/// **Constraints:** Allocates Strings freely — never call from a signal handler.
public enum CrashTextFormatter: Sendable {

    /// Formats an analyzed crash as plain text.
    ///
    /// - Parameter crash: Symbolicated crash model.
    /// - Returns: Multi-line plain text report.
    public static func string(from crash: AnalyzedCrash) -> String {
        var lines: [String] = []
        lines.append("DebugThings Crash")
        lines.append("=================")
        lines.append("Signal: \(crash.signal.name) (\(crash.signal.rawValue))  si_code=\(crash.siCode)")
        if let timestamp = crash.timestamp {
            lines.append("Time: \(ISO8601DateFormatter().string(from: timestamp))")
        } else {
            lines.append("Time: (unknown)")
        }
        lines.append("Thread: \(crash.threadID)")
        appendFlags(crash.flags, to: &lines)
        lines.append("")

        if let regs = crash.registers {
            lines.append("Faulting PC")
            if let frame = crash.frames.first {
                lines.append("  \(formatFrame(frame))")
            } else {
                lines.append("  \(hex(regs.pc))")
            }
            lines.append("")
            lines.append("Registers")
            lines.append("  pc=\(hex(regs.pc)) lr=\(hex(regs.lr)) sp=\(hex(regs.sp)) fp=\(hex(regs.fp))")
            lines.append("  cpsr=\(hex(regs.cpsr))")
            var row: [String] = []
            for i in 0..<29 {
                row.append("x\(i)=\(hex(regs.x[i]))")
                if row.count == 4 {
                    lines.append("  " + row.joined(separator: " "))
                    row.removeAll(keepingCapacity: true)
                }
            }
            if !row.isEmpty {
                lines.append("  " + row.joined(separator: " "))
            }
            lines.append("")
        }

        lines.append("Stack")
        if crash.frames.isEmpty {
            lines.append("  (no frames)")
        } else {
            for (index, frame) in crash.frames.enumerated() {
                lines.append(String(format: "  %2d  %@", index, formatFrame(frame)))
            }
        }
        lines.append("")

        lines.append("Images (\(crash.images.count))")
        for image in crash.images.prefix(64) {
            lines.append(
                "  \(hex(image.base))+\(hex(image.size))  \(image.uuidString)  \(image.lastPathComponent)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Formats a decoded (not yet symbolicated) crash as plain text.
    ///
    /// - Parameter crash: Raw decoded dump.
    /// - Returns: Multi-line plain text with addresses only.
    public static func string(from crash: DecodedCrash) -> String {
        var lines: [String] = []
        lines.append("DebugThings Crash (decoded)")
        lines.append("===========================")
        lines.append("Signal: \(CrashSignal(rawValue: crash.signal).name) (\(crash.signal))  si_code=\(crash.siCode)")
        lines.append("Arch: \(crash.architecture.name)  version=\(crash.version)")
        lines.append("Time: \(crash.timestamp)")
        lines.append("Thread: \(crash.threadID)")
        lines.append("")

        if let regs = crash.registers {
            lines.append("Registers")
            lines.append("  pc=\(hex(regs.pc)) lr=\(hex(regs.lr)) sp=\(hex(regs.sp)) fp=\(hex(regs.fp))")
            lines.append("")
        }

        lines.append("Stack addresses")
        if crash.frameAddresses.isEmpty {
            lines.append("  (none)")
        } else {
            for (index, address) in crash.frameAddresses.enumerated() {
                lines.append(String(format: "  %2d  %@", index, hex(address)))
            }
        }
        lines.append("")

        lines.append("Images (\(crash.images.count))")
        for image in crash.images.prefix(64) {
            let name = (image.path as NSString).lastPathComponent
            lines.append("  \(hex(image.base))+\(hex(image.size))  \(image.uuidString)  \(name)")
        }
        return lines.joined(separator: "\n")
    }

    /// Appends non-default heuristic flags.
    private static func appendFlags(_ flags: CrashAnalysisFlags, to lines: inout [String]) {
        var parts: [String] = []
        if flags.possibleStackIssue { parts.append("possibleStackIssue") }
        if flags.involvesSwiftRuntime { parts.append("swiftRuntime") }
        if flags.involvesUIKitOrAppKit { parts.append("uiFramework") }
        if !parts.isEmpty {
            lines.append("Flags: \(parts.joined(separator: ", "))")
        }
    }

    /// Formats one analyzed frame line.
    private static func formatFrame(_ frame: StackFrame) -> String {
        var parts = [hex(frame.address)]
        if let image = frame.image {
            let offset = frame.imageOffset.map { "+\(hex($0))" } ?? ""
            parts.append("\(image.lastPathComponent)\(offset)")
        }
        if let symbol = frame.symbol {
            let symOff = frame.symbolOffset.map { "+\(hex($0))" } ?? ""
            parts.append("\(symbol)\(symOff)")
        }
        return parts.joined(separator: "  ")
    }

    /// Hex string with `0x` prefix.
    private static func hex(_ value: UInt64) -> String {
        String(format: "0x%llX", value)
    }
}

/// Renders crash models as Markdown for rich text / issue bodies.
///
/// **What:** Same information as `CrashTextFormatter`, with headings and fenced code blocks.
/// **Why:** Convenient for GitHub issues or notes without depending on email/UI code.
/// **Constraints:** Allocates Strings — never call from a signal handler.
public enum CrashMarkdownFormatter: Sendable {

    /// Formats an analyzed crash as Markdown.
    ///
    /// - Parameter crash: Symbolicated crash model.
    /// - Returns: Markdown document string.
    public static func string(from crash: AnalyzedCrash) -> String {
        var md: [String] = []
        md.append("# DebugThings Crash")
        md.append("")
        md.append("- **Signal:** `\(crash.signal.name)` (\(crash.signal.rawValue)), si_code=\(crash.siCode)")
        if let timestamp = crash.timestamp {
            md.append("- **Time:** \(ISO8601DateFormatter().string(from: timestamp))")
        }
        md.append("- **Thread:** \(crash.threadID)")
        var flagParts: [String] = []
        if crash.flags.possibleStackIssue { flagParts.append("`possibleStackIssue`") }
        if crash.flags.involvesSwiftRuntime { flagParts.append("`swiftRuntime`") }
        if crash.flags.involvesUIKitOrAppKit { flagParts.append("`uiFramework`") }
        if !flagParts.isEmpty {
            md.append("- **Flags:** \(flagParts.joined(separator: ", "))")
        }
        md.append("")

        md.append("## Stack")
        md.append("")
        md.append("```")
        if crash.frames.isEmpty {
            md.append("(no frames)")
        } else {
            for (index, frame) in crash.frames.enumerated() {
                md.append(String(format: "%2d  %@", index, CrashTextFormatterLine.frame(frame)))
            }
        }
        md.append("```")
        md.append("")

        if let regs = crash.registers {
            md.append("## Registers")
            md.append("")
            md.append("```")
            md.append("pc=\(hex(regs.pc)) lr=\(hex(regs.lr)) sp=\(hex(regs.sp)) fp=\(hex(regs.fp))")
            md.append("cpsr=\(hex(regs.cpsr))")
            for i in 0..<29 {
                md.append("x\(i)=\(hex(regs.x[i]))")
            }
            md.append("```")
            md.append("")
        }

        md.append("## Images")
        md.append("")
        md.append("```")
        for image in crash.images.prefix(64) {
            md.append("\(hex(image.base))+\(hex(image.size))  \(image.uuidString)  \(image.lastPathComponent)")
        }
        md.append("```")
        return md.joined(separator: "\n")
    }

    /// Formats a decoded crash as Markdown (addresses only).
    ///
    /// - Parameter crash: Raw decoded dump.
    /// - Returns: Markdown document string.
    public static func string(from crash: DecodedCrash) -> String {
        var md: [String] = []
        md.append("# DebugThings Crash (decoded)")
        md.append("")
        md.append("- **Signal:** `\(CrashSignal(rawValue: crash.signal).name)` (\(crash.signal))")
        md.append("- **Arch:** \(crash.architecture.name)")
        md.append("- **Time:** \(crash.timestamp)")
        md.append("- **Thread:** \(crash.threadID)")
        md.append("")
        md.append("## Stack addresses")
        md.append("")
        md.append("```")
        if crash.frameAddresses.isEmpty {
            md.append("(none)")
        } else {
            for (index, address) in crash.frameAddresses.enumerated() {
                md.append(String(format: "%2d  %@", index, hex(address)))
            }
        }
        md.append("```")
        md.append("")
        md.append("## Images")
        md.append("")
        md.append("```")
        for image in crash.images.prefix(64) {
            let name = (image.path as NSString).lastPathComponent
            md.append("\(hex(image.base))+\(hex(image.size))  \(image.uuidString)  \(name)")
        }
        md.append("```")
        return md.joined(separator: "\n")
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "0x%llX", value)
    }
}

/// Shared frame line formatting used by Markdown output.
///
/// **Why:** Avoids exposing `CrashTextFormatter`'s private helpers while keeping lines identical.
enum CrashTextFormatterLine {
    /// Formats one analyzed frame the same way as the text formatter.
    static func frame(_ frame: StackFrame) -> String {
        var parts = [String(format: "0x%llX", frame.address)]
        if let image = frame.image {
            let offset = frame.imageOffset.map { String(format: "+0x%llX", $0) } ?? ""
            parts.append("\(image.lastPathComponent)\(offset)")
        }
        if let symbol = frame.symbol {
            let symOff = frame.symbolOffset.map { String(format: "+0x%llX", $0) } ?? ""
            parts.append("\(symbol)\(symOff)")
        }
        return parts.joined(separator: "  ")
    }
}
