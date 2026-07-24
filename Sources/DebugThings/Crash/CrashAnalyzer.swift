import Darwin
import Foundation
import MachO

/// Turns a `DecodedCrash` into an `AnalyzedCrash` with image attribution and best-effort symbols.
///
/// **What:** Maps crash-time addresses onto dump images, remaps into the current process when a
/// same-UUID image is still loaded, and calls `dladdr` for symbol names.
///
/// **Why:** Keeps symbolication out of the recorder (unsafe at crash time) and out of formatters
/// (presentation only).
///
/// **Constraints:** Absolute addresses from the dump are meaningless under a new ASLR slide unless
/// remapped via UUID. When remapping fails, frames still expose `image + offset`.
public enum CrashAnalyzer: Sendable {

    /// Analyzes a decoded dump in the current process.
    ///
    /// - Parameter crash: Output of `CrashDecoder`.
    /// - Returns: Symbolicated / attributed `AnalyzedCrash`.
    public static func analyze(_ crash: DecodedCrash) -> AnalyzedCrash {
        let currentImages = CurrentProcessImages.snapshot()
        let loadedImages: [LoadedImage] = crash.images.map { decoded in
            let match = currentImages.first { uuidEqual($0.uuid, decoded.uuid) }
            return LoadedImage(
                base: decoded.base,
                size: decoded.size,
                uuid: decoded.uuid,
                path: decoded.path,
                currentBase: match?.base
            )
        }

        var addresses = crash.frameAddresses
        if let pc = crash.registers?.pc, addresses.first != pc {
            addresses.insert(pc, at: 0)
        }
        // Deduplicate adjacent identical addresses.
        var uniqueAddresses: [UInt64] = []
        for address in addresses {
            if uniqueAddresses.last != address {
                uniqueAddresses.append(address)
            }
        }

        let frames = uniqueAddresses.map { address in
            resolveFrame(address: address, images: loadedImages)
        }

        let flags = deriveFlags(registers: crash.registers, frames: frames)
        let timestamp: Date? = crash.timestamp > 0
            ? Date(timeIntervalSince1970: TimeInterval(crash.timestamp))
            : nil

        return AnalyzedCrash(
            signal: CrashSignal(rawValue: crash.signal),
            siCode: crash.siCode,
            timestamp: timestamp,
            threadID: crash.threadID,
            registers: crash.registers,
            frames: frames,
            images: loadedImages,
            flags: flags
        )
    }

    /// Analyzes a dump file by decoding then analyzing.
    ///
    /// - Parameter url: Path to a `.dtcr` file.
    /// - Returns: Analyzed model.
    /// - Throws: Decode or I/O errors.
    public static func analyze(contentsOf url: URL) throws -> AnalyzedCrash {
        let decoded = try CrashDecoder.decode(contentsOf: url)
        return analyze(decoded)
    }

    /// Resolves one crash-time address into a `StackFrame`.
    ///
    /// - Parameters:
    ///   - address: Crash-time virtual address.
    ///   - images: Analyzed images from the dump.
    /// - Returns: Frame with optional image/symbol metadata.
    public static func resolveFrame(address: UInt64, images: [LoadedImage]) -> StackFrame {
        guard let image = images.first(where: { decodedContains(image: $0, address: address) }) else {
            return StackFrame(address: address)
        }
        let imageOffset = address &- image.base
        var symbol: String?
        var symbolOffset: UInt64?

        if let currentBase = image.currentBase {
            let remapped = currentBase &+ imageOffset
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: UInt(remapped)), &info) != 0,
               let name = info.dli_sname
            {
                symbol = String(cString: name)
                let symAddr = UInt64(UInt(bitPattern: info.dli_saddr))
                if remapped >= symAddr {
                    symbolOffset = remapped &- symAddr
                }
            }
        }

        return StackFrame(
            address: address,
            image: image,
            symbol: symbol,
            symbolOffset: symbolOffset,
            imageOffset: imageOffset
        )
    }

    /// Derives lightweight heuristic flags from registers and top frames.
    private static func deriveFlags(
        registers: ARM64Registers?,
        frames: [StackFrame]
    ) -> CrashAnalysisFlags {
        var flags = CrashAnalysisFlags()
        if let sp = registers?.sp, sp < 0x10000 {
            flags.possibleStackIssue = true
        }
        let paths = frames.prefix(8).compactMap { $0.image?.path.lowercased() }
        flags.involvesSwiftRuntime = paths.contains { path in
            path.contains("libswiftcore") || path.contains("libswift") || path.contains("swiftcore")
        }
        flags.involvesUIKitOrAppKit = paths.contains { path in
            path.contains("uikit") || path.contains("appkit") || path.contains("swiftui")
        }
        return flags
    }

    /// Range test using crash-time base/size.
    private static func decodedContains(image: LoadedImage, address: UInt64) -> Bool {
        guard image.size > 0 else { return false }
        return address >= image.base && address < image.base &+ image.size
    }

    /// Compares two `uuid_t` values.
    private static func uuidEqual(_ lhs: uuid_t, _ rhs: uuid_t) -> Bool {
        withUnsafeBytes(of: lhs) { left in
            withUnsafeBytes(of: rhs) { right in
                memcmp(left.baseAddress, right.baseAddress, 16) == 0
            }
        }
    }
}

/// Snapshot of images currently loaded in this process (for UUID remapping).
///
/// **What:** Enumerates dyld images with UUID + load base.
/// **Why:** Enables `dladdr` against remapped crash addresses when the same binary is still mapped.
enum CurrentProcessImages {
    /// One currently loaded image.
    struct Image {
        var base: UInt64
        var uuid: uuid_t
        var path: String
    }

    /// Builds a best-effort list of currently loaded Mach-O images.
    static func snapshot() -> [Image] {
        var result: [Image] = []
        let count = Int(_dyld_image_count())
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let header = _dyld_get_image_header(UInt32(index)) else { continue }
            let path = _dyld_get_image_name(UInt32(index)).map { String(cString: $0) } ?? ""
            let uuid = uuid(from: header)
            result.append(
                Image(
                    base: UInt64(UInt(bitPattern: header)),
                    uuid: uuid,
                    path: path
                )
            )
        }
        return result
    }

    /// Reads `LC_UUID` from a Mach-O header.
    private static func uuid(from header: UnsafePointer<mach_header>) -> uuid_t {
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        let is64 = header.pointee.magic == MH_MAGIC_64 || header.pointee.magic == MH_CIGAM_64
        let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        var cmdPtr = UnsafeRawPointer(header).advanced(by: headerSize)
        for _ in 0..<Int(header.pointee.ncmds) {
            let cmd = cmdPtr.assumingMemoryBound(to: load_command.self).pointee
            if cmd.cmd == LC_UUID {
                uuid = cmdPtr.assumingMemoryBound(to: uuid_command.self).pointee.uuid
                break
            }
            cmdPtr = cmdPtr.advanced(by: Int(cmd.cmdsize))
        }
        return uuid
    }
}
