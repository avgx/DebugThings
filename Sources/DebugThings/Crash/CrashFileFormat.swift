import Foundation

/// Constants and layout helpers for the DebugThings crash mini-dump file (`.dtcr`).
///
/// **What:** Defines magic, version, architecture tags, section limits, and checksum
/// used by `CrashRecorder` (writer) and `CrashDecoder` (reader).
///
/// **Why:** A fixed little-endian POD layout keeps the signal-time writer free of JSON/Foundation
/// and lets the next launch decode a stable binary snapshot.
///
/// **Constraints:** Field sizes and section order must stay in sync with
/// `CrashBinaryWriter` / `CrashDecoder`. Changing `version` requires a matching decoder path.
public enum CrashFileFormat: Sendable {

    /// File magic `DTCR` as a little-endian `UInt32` (`0x44544352`).
    ///
    /// Used to reject unrelated files before any further parsing.
    public static let magic: UInt32 = 0x4454_4352

    /// Current on-disk format version written by `CrashRecorder`.
    public static let version: UInt32 = 1

    /// Architecture tag stored in the header for arm64 register layouts.
    public static let archARM64: UInt32 = 1

    /// Maximum stack frames captured via frame-pointer unwind in the signal handler.
    ///
    /// Keeps the static capture buffer bounded and async-signal-safe.
    public static let maxFrames: Int = 64

    /// Maximum Mach-O images snapshotted into the dump from the prebuilt image table.
    public static let maxImages: Int = 128

    /// Maximum bytes reserved for concatenated UTF-8 image paths in the dump.
    public static let maxPathTableBytes: Int = 16 * 1024

    /// Maximum length of a single image path copied into the path table (including NUL).
    public static let maxPathLength: Int = 1024

    /// Byte size of the fixed file header preceding registers/frames/images.
    ///
    /// Layout (little-endian):
    /// magic, version, arch, signal, siCode, flags,
    /// timestamp, threadID,
    /// frameCount, imageCount, pathTableByteCount, reserved,
    /// then payload… then trailing checksum `UInt32`.
    public static let headerByteCount: Int = 56

    /// Byte size of the arm64 register blob (`x0…x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`).
    public static let arm64RegisterByteCount: Int = 34 * 8

    /// Minimum valid file size: header + empty payload + checksum.
    public static let minimumValidFileByteCount: Int = headerByteCount + 4

    /// Filename of the pending crash dump left for the next launch to analyze.
    public static let pendingFileName = "crash.dtcr"

    /// Filename of the per-session capture file the signal handler writes into.
    ///
    /// **Why separate from pending:** `install` must open a writable FD with `O_TRUNC`
    /// without destroying a previous crash that still needs analysis.
    public static let captureFileName = "crash.capture.dtcr"

    /// Computes a simple additive checksum over `bytes`.
    ///
    /// **What:** Sums all bytes into a `UInt32` (wrapping).
    /// **Why:** Cheap integrity check that is safe to run both in the writer (after filling
    /// a static buffer) and in the decoder; not a cryptographic hash.
    /// **Constraints:** Must match between writer and decoder; do not include the trailing
    /// checksum word itself in the summed range.
    ///
    /// - Parameter bytes: Payload bytes excluding the trailing checksum field.
    /// - Returns: Wrapping sum of all bytes.
    public static func checksum(of bytes: UnsafeRawBufferPointer) -> UInt32 {
        var sum: UInt32 = 0
        for b in bytes {
            sum &+= UInt32(b)
        }
        return sum
    }

    /// Convenience overload that checksums a `Data` value.
    ///
    /// - Parameter data: Payload bytes excluding the trailing checksum field.
    /// - Returns: Wrapping byte sum.
    public static func checksum(of data: Data) -> UInt32 {
        data.withUnsafeBytes { checksum(of: $0) }
    }
}

/// CPU architecture recorded in a crash dump header.
///
/// **What:** Distinguishes register layouts so the decoder can reject unsupported blobs.
/// **Why:** MVP focuses on arm64; other arches fail decode with a clear error.
public enum CrashArchitecture: UInt32, Sendable, Equatable {
    /// AArch64 / ARM64 register set (`x0…x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`).
    case arm64 = 1

    /// Human-readable architecture name for formatters and diagnostics.
    public var name: String {
        switch self {
        case .arm64: return "arm64"
        }
    }
}
