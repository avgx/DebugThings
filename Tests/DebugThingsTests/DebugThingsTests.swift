import Foundation
import Logging
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
