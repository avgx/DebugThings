import Foundation

/// Errors produced while decoding a `.dtcr` crash mini-dump.
///
/// **What:** Distinguishes truncated files, bad magic/version, checksum mismatch, and unsupported arch.
/// **Why:** Callers can decide whether to discard a corrupt pending file or surface diagnostics.
public enum CrashDecodeError: Error, Sendable, Equatable {
    /// File shorter than the fixed header + checksum.
    case truncated
    /// Magic word is not `CrashFileFormat.magic`.
    case badMagic(UInt32)
    /// Version is newer/unknown to this decoder.
    case unsupportedVersion(UInt32)
    /// Architecture tag has no register layout in this library build.
    case unsupportedArchitecture(UInt32)
    /// Trailing checksum does not match the payload.
    case checksumMismatch(expected: UInt32, actual: UInt32)
    /// Counts imply a payload larger than the available bytes.
    case malformedPayload(String)
}

/// Encodes crash snapshots into the `.dtcr` little-endian layout.
///
/// **What:** Builds header + registers + frames + images + path table + checksum as `Data`.
/// **Why:** Shared by unit tests (synthetic dumps) and by the recorder’s safe-path helpers that
/// prepare buffers; the signal handler uses the same field order via `CrashRecorderStorage`.
/// **Constraints:** Not async-signal-safe (`Data` allocates). Never call from a signal handler.
public enum CrashBinaryEncoder: Sendable {

    /// Encodes a `DecodedCrash`-shaped snapshot into file bytes.
    ///
    /// - Parameter crash: Logical dump contents (typically synthetic in tests).
    /// - Returns: Complete `.dtcr` file bytes including trailing checksum.
    /// - Throws: `CrashDecodeError.unsupportedArchitecture` if registers cannot be serialized.
    public static func encode(_ crash: DecodedCrash) throws -> Data {
        guard crash.architecture == .arm64 else {
            throw CrashDecodeError.unsupportedArchitecture(crash.architecture.rawValue)
        }
        let frames = Array(crash.frameAddresses.prefix(CrashFileFormat.maxFrames))
        let images = Array(crash.images.prefix(CrashFileFormat.maxImages))

        var pathTable = Data()
        var imageRecords: [(base: UInt64, size: UInt64, uuid: uuid_t, pathOffset: UInt32, pathLength: UInt32)] = []
        for image in images {
            let pathData = Data(image.path.utf8.prefix(CrashFileFormat.maxPathLength - 1))
            let offset = UInt32(pathTable.count)
            let length = UInt32(pathData.count)
            if pathTable.count + pathData.count > CrashFileFormat.maxPathTableBytes {
                break
            }
            pathTable.append(pathData)
            imageRecords.append((image.base, image.size, image.uuid, offset, length))
        }

        var payload = Data()
        payload.reserveCapacity(
            CrashFileFormat.headerByteCount
                + CrashFileFormat.arm64RegisterByteCount
                + frames.count * 8
                + imageRecords.count * CrashImageRecord.byteCount
                + pathTable.count
                + 4
        )

        appendUInt32(CrashFileFormat.magic, to: &payload)
        appendUInt32(crash.version, to: &payload)
        appendUInt32(crash.architecture.rawValue, to: &payload)
        appendUInt32(UInt32(bitPattern: crash.signal), to: &payload)
        appendInt32(crash.siCode, to: &payload)
        appendUInt32(0, to: &payload) // flags
        appendUInt64(crash.timestamp, to: &payload)
        appendUInt64(crash.threadID, to: &payload)
        appendUInt32(UInt32(frames.count), to: &payload)
        appendUInt32(UInt32(imageRecords.count), to: &payload)
        appendUInt32(UInt32(pathTable.count), to: &payload)
        appendUInt32(0, to: &payload) // reserved

        let regs = crash.registers ?? ARM64Registers()
        for i in 0..<29 {
            appendUInt64(regs.x[i], to: &payload)
        }
        appendUInt64(regs.fp, to: &payload)
        appendUInt64(regs.lr, to: &payload)
        appendUInt64(regs.sp, to: &payload)
        appendUInt64(regs.pc, to: &payload)
        appendUInt64(regs.cpsr, to: &payload)

        for address in frames {
            appendUInt64(address, to: &payload)
        }
        for record in imageRecords {
            appendUInt64(record.base, to: &payload)
            appendUInt64(record.size, to: &payload)
            withUnsafeBytes(of: record.uuid) { payload.append(contentsOf: $0) }
            appendUInt32(record.pathOffset, to: &payload)
            appendUInt32(record.pathLength, to: &payload)
        }
        payload.append(pathTable)

        let sum = CrashFileFormat.checksum(of: payload)
        appendUInt32(sum, to: &payload)
        return payload
    }

    /// On-disk size of one image record excluding path bytes.
    enum CrashImageRecord {
        /// base(8) + size(8) + uuid(16) + pathOffset(4) + pathLength(4).
        static let byteCount = 8 + 8 + 16 + 4 + 4
    }
}

/// Decodes `.dtcr` bytes into `DecodedCrash`.
///
/// **What:** Validates magic/version/checksum and parses POD sections into Swift models.
/// **Why:** Isolates binary parsing from symbolication so corrupt files fail before analysis.
/// **Constraints:** Safe to run only in a healthy process (allocates Strings/Arrays).
public enum CrashDecoder: Sendable {

    /// Decodes crash dump bytes.
    ///
    /// - Parameter data: Complete file contents including checksum.
    /// - Returns: Structured `DecodedCrash`.
    /// - Throws: `CrashDecodeError` on validation or structural failure.
    public static func decode(_ data: Data) throws -> DecodedCrash {
        guard data.count >= CrashFileFormat.minimumValidFileByteCount else {
            throw CrashDecodeError.truncated
        }

        let checksumOffset = data.count - 4
        let payload = data.prefix(checksumOffset)
        let expected = CrashFileFormat.checksum(of: Data(payload))
        let actual = readUInt32(data, at: checksumOffset)
        guard expected == actual else {
            throw CrashDecodeError.checksumMismatch(expected: expected, actual: actual)
        }

        var offset = 0
        let magic = readUInt32(data, at: &offset)
        guard magic == CrashFileFormat.magic else {
            throw CrashDecodeError.badMagic(magic)
        }
        let version = readUInt32(data, at: &offset)
        guard version == CrashFileFormat.version else {
            throw CrashDecodeError.unsupportedVersion(version)
        }
        let archRaw = readUInt32(data, at: &offset)
        guard let architecture = CrashArchitecture(rawValue: archRaw) else {
            throw CrashDecodeError.unsupportedArchitecture(archRaw)
        }
        let signal = Int32(bitPattern: readUInt32(data, at: &offset))
        let siCode = readInt32(data, at: &offset)
        _ = readUInt32(data, at: &offset) // flags
        let timestamp = readUInt64(data, at: &offset)
        let threadID = readUInt64(data, at: &offset)
        let frameCount = Int(readUInt32(data, at: &offset))
        let imageCount = Int(readUInt32(data, at: &offset))
        let pathTableByteCount = Int(readUInt32(data, at: &offset))
        _ = readUInt32(data, at: &offset) // reserved

        guard offset == CrashFileFormat.headerByteCount else {
            throw CrashDecodeError.malformedPayload("header size mismatch")
        }
        guard frameCount >= 0, frameCount <= CrashFileFormat.maxFrames,
              imageCount >= 0, imageCount <= CrashFileFormat.maxImages,
              pathTableByteCount >= 0, pathTableByteCount <= CrashFileFormat.maxPathTableBytes
        else {
            throw CrashDecodeError.malformedPayload("section counts out of range")
        }

        let registers: ARM64Registers?
        if architecture == .arm64 {
            guard data.count >= offset + CrashFileFormat.arm64RegisterByteCount + 4 else {
                throw CrashDecodeError.truncated
            }
            var x = [UInt64](repeating: 0, count: 29)
            for i in 0..<29 {
                x[i] = readUInt64(data, at: &offset)
            }
            let fp = readUInt64(data, at: &offset)
            let lr = readUInt64(data, at: &offset)
            let sp = readUInt64(data, at: &offset)
            let pc = readUInt64(data, at: &offset)
            let cpsr = readUInt64(data, at: &offset)
            registers = ARM64Registers(x: x, fp: fp, lr: lr, sp: sp, pc: pc, cpsr: cpsr)
        } else {
            registers = nil
        }

        var frames: [UInt64] = []
        frames.reserveCapacity(frameCount)
        for _ in 0..<frameCount {
            guard data.count >= offset + 8 + 4 else { throw CrashDecodeError.truncated }
            frames.append(readUInt64(data, at: &offset))
        }

        let imageRecordsByteCount = imageCount * CrashBinaryEncoder.CrashImageRecord.byteCount
        guard data.count >= offset + imageRecordsByteCount + pathTableByteCount + 4 else {
            throw CrashDecodeError.truncated
        }

        var rawImages: [(base: UInt64, size: UInt64, uuid: uuid_t, pathOffset: UInt32, pathLength: UInt32)] = []
        for _ in 0..<imageCount {
            let base = readUInt64(data, at: &offset)
            let size = readUInt64(data, at: &offset)
            var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            _ = withUnsafeMutableBytes(of: &uuid) { uuidBytes in
                data.copyBytes(to: uuidBytes, from: offset..<(offset + 16))
            }
            offset += 16
            let pathOffset = readUInt32(data, at: &offset)
            let pathLength = readUInt32(data, at: &offset)
            rawImages.append((base, size, uuid, pathOffset, pathLength))
        }

        let pathTableStart = offset
        let pathTable = data.subdata(in: pathTableStart..<(pathTableStart + pathTableByteCount))
        offset += pathTableByteCount

        guard offset == checksumOffset else {
            throw CrashDecodeError.malformedPayload("payload end mismatch")
        }

        var images: [DecodedLoadedImage] = []
        for raw in rawImages {
            let path: String
            if raw.pathLength == 0 {
                path = ""
            } else {
                let start = Int(raw.pathOffset)
                let end = start + Int(raw.pathLength)
                guard start >= 0, end <= pathTable.count else {
                    throw CrashDecodeError.malformedPayload("path out of table bounds")
                }
                path = String(decoding: pathTable[start..<end], as: UTF8.self)
            }
            images.append(DecodedLoadedImage(base: raw.base, size: raw.size, uuid: raw.uuid, path: path))
        }

        return DecodedCrash(
            version: version,
            architecture: architecture,
            signal: signal,
            siCode: siCode,
            timestamp: timestamp,
            threadID: threadID,
            registers: registers,
            frameAddresses: frames,
            images: images
        )
    }

    /// Decodes a crash dump from a file URL.
    ///
    /// - Parameter url: Path to a `.dtcr` file.
    /// - Returns: Structured `DecodedCrash`.
    /// - Throws: File I/O errors or `CrashDecodeError`.
    public static func decode(contentsOf url: URL) throws -> DecodedCrash {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }
}

// MARK: - Binary primitives

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var le = value.littleEndian
    withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
}

private func appendInt32(_ value: Int32, to data: inout Data) {
    appendUInt32(UInt32(bitPattern: value), to: &data)
}

private func appendUInt64(_ value: UInt64, to data: inout Data) {
    var le = value.littleEndian
    withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
}

private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    var value: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &value) { buffer in
        data.copyBytes(to: buffer, from: offset..<(offset + 4))
    }
    return UInt32(littleEndian: value)
}

private func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
    let value = readUInt32(data, at: offset)
    offset += 4
    return value
}

private func readInt32(_ data: Data, at offset: inout Int) -> Int32 {
    Int32(bitPattern: readUInt32(data, at: &offset))
}

private func readUInt64(_ data: Data, at offset: inout Int) -> UInt64 {
    var value: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &value) { buffer in
        data.copyBytes(to: buffer, from: offset..<(offset + 8))
    }
    offset += 8
    return UInt64(littleEndian: value)
}
