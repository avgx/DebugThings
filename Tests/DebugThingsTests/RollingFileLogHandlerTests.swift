import Foundation
import Logging
import Testing

@testable import DebugThings

private func makeLogDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RollingFileLogHandlerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func fileSize(_ url: URL) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? Int) ?? -1
}

private func readText(_ url: URL) -> String {
    String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
}

private func emit(_ handler: RollingFileLogHandler, _ message: String) {
    handler.log(level: .info, message: "\(message)", metadata: nil, source: "test", file: "test", function: "test", line: 1)
}

/// Returns the message of a full line produced by `FileLogHandler.formatLine`
/// (`HH:mm:ss.SSS [INFO ] <message>`), or nil if the line is not intact.
private func lineMessage(_ line: String) -> String? {
    guard let match = line.firstMatch(of: /^\d{2}:\d{2}:\d{2}\.\d{3} \[INFO \] (.+)$/) else { return nil }
    return String(match.1)
}

@Suite("RollingFileLogHandler", .serialized)
struct RollingFileLogHandlerTests {

    @Test
    func defaultCapIs16KiB() {
        #expect(RollingFileLogHandler.defaultMaxFileBytes == 16 * 1024)
    }

    @Test
    func activeFileStaysUnderCap() throws {
        let directory = try makeLogDirectory()
        let logURL = directory.appendingPathComponent("run.log")
        let cap = 512
        let handler = try RollingFileLogHandler(label: "cap", logFileURL: logURL, maxFileBytes: cap)

        for index in 0..<200 {
            emit(handler, "cap-\(index)-\(String(repeating: "x", count: 40))")
            #expect(fileSize(logURL) <= cap, "active file exceeded cap after line \(index)")
        }
    }

    @Test
    func rotationKeepsPreviousContentInSingleBackup() throws {
        let directory = try makeLogDirectory()
        let logURL = directory.appendingPathComponent("run.log")
        let backupURL = directory.appendingPathComponent("run.log.1")
        let handler = try RollingFileLogHandler(label: "backup", logFileURL: logURL, maxFileBytes: 512)

        for index in 0..<100 {
            emit(handler, "M-\(index)-\(String(repeating: "m", count: 40))")
        }

        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(!readText(backupURL).isEmpty, "backup must hold the rotated content, not be empty")
        #expect(readText(backupURL).hasSuffix("\n"), "backup must end on a whole line")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("run.log.2").path))

        // Backup and active file together hold a consecutive run of lines ending at the last write.
        let combined = readText(backupURL) + readText(logURL)
        let messages = combined.split(separator: "\n").compactMap { line -> Int? in
            guard let message = lineMessage(String(line)) else { return nil }
            return Int(message.split(separator: "-")[1])
        }
        #expect(messages.last == 99)
        #expect(!messages.isEmpty)
        for (previous, next) in zip(messages, messages.dropFirst()) {
            #expect(next == previous + 1, "gap between lines \(previous) and \(next)")
        }
    }

    @Test
    func backupIsReplacedNotAccumulated() throws {
        let directory = try makeLogDirectory()
        let logURL = directory.appendingPathComponent("run.log")
        let backupURL = directory.appendingPathComponent("run.log.1")
        let handler = try RollingFileLogHandler(label: "replace", logFileURL: logURL, maxFileBytes: 256)

        for index in 0..<300 {
            emit(handler, "R-\(index)-\(String(repeating: "r", count: 40))")
        }

        // The backup only ever holds one rotation's worth of content, so it stays near the cap.
        #expect(fileSize(backupURL) <= 256)
        #expect(fileSize(logURL) <= 256)
    }

    @Test
    func handlersOnSamePathKeepWritingAfterRotation() async throws {
        let directory = try makeLogDirectory()
        let logURL = directory.appendingPathComponent("run.log")
        let handlerA = try RollingFileLogHandler(label: "label-a", logFileURL: logURL, maxFileBytes: 512)

        for index in 0..<30 {
            emit(handlerA, "A-\(index)-\(String(repeating: "a", count: 40))")
        }
        // Created after A has already rotated the file; must append to the same inode.
        let handlerB = try RollingFileLogHandler(label: "label-b", logFileURL: logURL, maxFileBytes: 512)
        for index in 0..<30 {
            emit(handlerA, "A2-\(index)-\(String(repeating: "y", count: 40))")
            emit(handlerB, "B-\(index)-\(String(repeating: "z", count: 40))")
        }

        let active = readText(logURL)
        let backup = readText(directory.appendingPathComponent("run.log.1"))

        // Every line in both files is intact.
        for line in (active + backup).split(separator: "\n") {
            #expect(lineMessage(String(line)) != nil, "corrupted line: \(line.prefix(80))")
        }
        // The last write came from B and must be in the active file, proving B kept writing
        // to the rotated file rather than to a stale descriptor.
        #expect(active.contains("B-29-"))
        #expect(fileSize(logURL) <= 512)
    }

    @Test
    func singleOversizedLineIsWrittenWhole() throws {
        let directory = try makeLogDirectory()
        let logURL = directory.appendingPathComponent("run.log")
        let backupURL = directory.appendingPathComponent("run.log.1")
        let handler = try RollingFileLogHandler(label: "big", logFileURL: logURL, maxFileBytes: 64)

        let big = String(repeating: "B", count: 200)
        emit(handler, "BIG-\(big)")
        #expect(readText(logURL).contains("BIG-\(big)"))
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))

        // The next write rotates the oversized line into the backup.
        emit(handler, "after")
        #expect(readText(backupURL).contains("BIG-\(big)"))
        #expect(readText(logURL).contains("after"))
        #expect(!readText(logURL).contains("BIG-"))
    }
}
