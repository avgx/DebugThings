import Foundation
import Logging
import OSLogHandler
import Testing

@testable import DebugThings

private struct DemoService: Loggable {}

@Suite("DebugThings (serialized SwiftLog bootstrap)", .serialized)
struct DebugThingsSerializedTests {

    @Test
    func loggableSubsystemContainsLowercasedTypeName() {
        #expect(DemoService.subsystem.lowercased().contains("demoservice"))
    }

    @Test
    func bootstrapFileWritesSwiftLogOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugThingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("run.log", isDirectory: false)

        DebugThings.bootstrapFile(level: .info, logFileURL: logURL, subsystem: "com.debugthings.tests")

        let logger = Logger(label: "bootstrap-file-test")
        logger.info("bootstrap-file-test-marker")

        let data = try Data(contentsOf: logURL)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("bootstrap-file-test-marker"))
        print("[DebugThingsTests] tail of log file:\n\(text.suffix(500))")
    }
}

/// The SwiftLog bootstrap factory creates one FileLogHandler per logger label,
/// lazily. With a once-per-handle `seekToEndOfFile()` the independently seeked
/// file handles wrote at stale offsets and overwrote each other's bytes
/// (observed with onvif-probe: three package loggers produced corrupted lines
/// such as "23:23:54:31.213"). The O_APPEND open makes every write land at the
/// file's current end regardless of offsets; this test reproduces the failure
/// shape by interleaving two handlers created at different times.
@Suite("FileLogHandler (multi-label appends)", .serialized)
struct FileLogHandlerAppendTests {

    @Test
    func lazilyCreatedHandlersAppendWithoutOverwritingEachOther() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLogHandlerAppendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("run.log", isDirectory: false)

        // Handler A is created and used first; handler B is created only after
        // A has already written — with the old seek-once behavior B's offset
        // snapshot pointed into the middle of A's output.
        let handlerA = try FileLogHandler(label: "label-a", logFileURL: logURL)
        for index in 0..<20 {
            handlerA.log(level: .info, message: "A-\(index)-\(String(repeating: "x", count: 40))", metadata: nil, source: "test", file: "test", function: "test", line: 1)
        }

        let handlerB = try FileLogHandler(label: "label-b", logFileURL: logURL)
        // Interleave: both handles keep writing after B exists.
        for index in 0..<20 {
            handlerA.log(level: .info, message: "A2-\(index)-\(String(repeating: "y", count: 40))", metadata: nil, source: "test", file: "test", function: "test", line: 1)
            handlerB.log(level: .info, message: "B-\(index)-\(String(repeating: "z", count: 40))", metadata: nil, source: "test", file: "test", function: "test", line: 1)
        }

        let text = String(decoding: try Data(contentsOf: logURL), as: UTF8.self)
        // Every line must be intact: no partial timestamps, no overwritten tails.
        let lines = text.split(separator: "\n")
        #expect(lines.count == 60)
        for line in lines {
            let pattern = /^\d{2}:\d{2}:\d{2}\.\d{3} \[INFO \] (A-\d+|A2-\d+|B-\d+)-[xyz]{40}$/
            #expect(line.firstMatch(of: pattern) != nil, "corrupted line: \(line.prefix(80))")
        }
        // Nothing lost, nothing duplicated by offset races.
        for index in 0..<20 {
            #expect(text.contains("A2-\(index)-"))
            #expect(text.contains("B-\(index)-"))
        }
    }
}

@Test
func explicitLogLevelOverridesSystemEnablement() {
    var handler = OSLogHandler(subsystem: "com.debugthings.tests", category: "level")
    handler.logLevel = .info
    #expect(handler.logLevel == .info)
    handler.logLevel = .critical
    #expect(handler.logLevel == .critical)
}

@Test
func osLogHandlerWithoutExplicitLevelDoesNotCrash() {
    let handler = OSLogHandler(subsystem: "com.debugthings.tests", category: "smoke")
    _ = handler.logLevel
    handler.log(
        event: LogEvent(
            level: .info,
            message: "bootstrap-oslog-smoke-marker",
            metadata: nil,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )
    )
}
