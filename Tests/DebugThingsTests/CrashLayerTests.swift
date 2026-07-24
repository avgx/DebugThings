import Foundation
import Testing
@testable import DebugThings

@Suite("Crash decode / analyze / format", .serialized)
struct CrashLayerTests {

    @Test
    func encodeDecodeRoundTripPreservesFields() throws {
        let uuid = UUID().uuid
        let crash = DecodedCrash(
            version: CrashFileFormat.version,
            architecture: .arm64,
            signal: SIGSEGV,
            siCode: 1,
            timestamp: 1_700_000_000,
            threadID: 42,
            registers: ARM64Registers(
                x: Array(0..<29).map { UInt64($0) },
                fp: 0x100,
                lr: 0x200,
                sp: 0x300,
                pc: 0x400,
                cpsr: 0x500
            ),
            frameAddresses: [0x400, 0x200, 0xABCD],
            images: [
                DecodedLoadedImage(
                    base: 0x1_0000_0000,
                    size: 0x10_0000,
                    uuid: uuid,
                    path: "/App.app/App"
                ),
            ]
        )

        let data = try CrashBinaryEncoder.encode(crash)
        let decoded = try CrashDecoder.decode(data)

        #expect(decoded.version == crash.version)
        #expect(decoded.architecture == .arm64)
        #expect(decoded.signal == SIGSEGV)
        #expect(decoded.siCode == 1)
        #expect(decoded.timestamp == 1_700_000_000)
        #expect(decoded.threadID == 42)
        #expect(decoded.registers?.pc == 0x400)
        #expect(decoded.registers?.lr == 0x200)
        #expect(decoded.frameAddresses == [0x400, 0x200, 0xABCD])
        #expect(decoded.images.count == 1)
        #expect(decoded.images[0].path == "/App.app/App")
        #expect(decoded.images[0].base == 0x1_0000_0000)
    }

    @Test
    func decodeRejectsBadMagic() throws {
        var data = try CrashBinaryEncoder.encode(sampleDecodedCrash())
        data[0] = 0x00
        #expect(throws: CrashDecodeError.self) {
            _ = try CrashDecoder.decode(data)
        }
    }

    @Test
    func decodeRejectsChecksumMismatch() throws {
        var data = try CrashBinaryEncoder.encode(sampleDecodedCrash())
        // Flip a payload byte before the trailing checksum.
        data[20] ^= 0xFF
        #expect(throws: CrashDecodeError.self) {
            _ = try CrashDecoder.decode(data)
        }
    }

    @Test
    func analyzerAttributesFramesToImages() throws {
        let base: UInt64 = 0x1_0000_0000
        let uuid = UUID().uuid
        let decoded = DecodedCrash(
            version: 1,
            architecture: .arm64,
            signal: SIGABRT,
            siCode: 0,
            timestamp: 100,
            threadID: 1,
            registers: ARM64Registers(pc: base + 0x1234),
            frameAddresses: [base + 0x1234, base + 0x2222],
            images: [
                DecodedLoadedImage(base: base, size: 0x10000, uuid: uuid, path: "/tmp/Demo"),
            ]
        )

        let analyzed = CrashAnalyzer.analyze(decoded)
        #expect(analyzed.signal == .abrt)
        #expect(analyzed.frames.count >= 1)
        #expect(analyzed.frames[0].imageOffset == 0x1234)
        #expect(analyzed.frames[0].image?.path == "/tmp/Demo")
    }

    @Test
    func textAndMarkdownFormattersContainSignalAndStack() {
        let analyzed = AnalyzedCrash(
            signal: .segv,
            siCode: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            threadID: 7,
            registers: ARM64Registers(fp: 0x4000, lr: 0x2000, sp: 0x3000, pc: 0x1000),
            frames: [
                StackFrame(
                    address: 0x1000,
                    image: LoadedImage(
                        base: 0x1000,
                        size: 0x1000,
                        uuid: UUID().uuid,
                        path: "/App.app/App"
                    ),
                    symbol: "Demo.crash",
                    symbolOffset: 0x10,
                    imageOffset: 0
                ),
            ],
            images: [
                LoadedImage(
                    base: 0x1000,
                    size: 0x1000,
                    uuid: UUID().uuid,
                    path: "/App.app/App"
                ),
            ],
            flags: CrashAnalysisFlags(possibleStackIssue: true)
        )

        let text = CrashTextFormatter.string(from: analyzed)
        #expect(text.contains("SIGSEGV"))
        #expect(text.contains("Demo.crash"))
        #expect(text.contains("possibleStackIssue"))

        let markdown = CrashMarkdownFormatter.string(from: analyzed)
        #expect(markdown.contains("# DebugThings Crash"))
        #expect(markdown.contains("SIGSEGV"))
        #expect(markdown.contains("```"))

        let decodedText = CrashTextFormatter.string(from: sampleDecodedCrash())
        #expect(decodedText.contains("decoded"))
        #expect(decodedText.contains("SIGSEGV"))
    }

    @Test
    func installUninstallDoesNotCreatePendingCrash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugThingsCrashTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        CrashRecorder.install(directory: directory)
        #expect(!CrashRecorder.hasPendingCrash)
        CrashRecorder.uninstall()
        #expect(!CrashRecorder.hasPendingCrash)
    }

    @Test
    func promoteCaptureBecomesPendingOnNextInstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugThingsCrashPromote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent(CrashFileFormat.captureFileName)
        let data = try CrashBinaryEncoder.encode(sampleDecodedCrash())
        try data.write(to: capture)

        CrashRecorder.install(directory: directory)
        defer { CrashRecorder.uninstall(); CrashRecorder.clearPendingCrash() }

        #expect(CrashRecorder.hasPendingCrash)
        let pending = try #require(CrashRecorder.consumePendingCrashFile())
        let decoded = try CrashDecoder.decode(contentsOf: pending)
        #expect(decoded.signal == SIGSEGV)

        let analyzed = try CrashAnalyzer.analyze(contentsOf: pending)
        #expect(analyzed.signal == .segv)

        CrashRecorder.clearPendingCrash()
        #expect(!CrashRecorder.hasPendingCrash)
    }
}

/// Shared synthetic dump for negative and formatter tests.
private func sampleDecodedCrash() -> DecodedCrash {
    DecodedCrash(
        version: CrashFileFormat.version,
        architecture: .arm64,
        signal: SIGSEGV,
        siCode: 1,
        timestamp: 123,
        threadID: 1,
        registers: ARM64Registers(fp: 0x40, lr: 0x20, sp: 0x30, pc: 0x10),
        frameAddresses: [0x10, 0x20],
        images: [
            DecodedLoadedImage(
                base: 0x1000,
                size: 0x1000,
                uuid: UUID().uuid,
                path: "/tmp/sample"
            ),
        ]
    )
}
