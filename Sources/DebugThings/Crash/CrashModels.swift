import Foundation

/// POSIX signal identity captured at crash time and surfaced after decode/analyze.
///
/// **What:** Maps well-known fatal signal numbers to named cases; unknown values stay `.other`.
/// **Why:** Analyzer and formatters need a stable vocabulary without depending on libc string tables.
/// **Constraints:** Only signals installed by `CrashRecorder` are expected in practice.
public enum CrashSignal: Sendable, Equatable, Hashable {
    case abrt
    case segv
    case bus
    case ill
    case fpe
    case trap
    /// Signal number not mapped to a dedicated case.
    case other(Int32)

    /// Creates a `CrashSignal` from a raw POSIX signal number.
    ///
    /// - Parameter rawValue: `signum` as stored in the dump header.
    public init(rawValue: Int32) {
        switch rawValue {
        case SIGABRT: self = .abrt
        case SIGSEGV: self = .segv
        case SIGBUS: self = .bus
        case SIGILL: self = .ill
        case SIGFPE: self = .fpe
        case SIGTRAP: self = .trap
        default: self = .other(rawValue)
        }
    }

    /// Raw POSIX signal number.
    public var rawValue: Int32 {
        switch self {
        case .abrt: return SIGABRT
        case .segv: return SIGSEGV
        case .bus: return SIGBUS
        case .ill: return SIGILL
        case .fpe: return SIGFPE
        case .trap: return SIGTRAP
        case .other(let value): return value
        }
    }

    /// Short signal name suitable for reports (`SIGSEGV`, `SIGABRT`, …).
    public var name: String {
        switch self {
        case .abrt: return "SIGABRT"
        case .segv: return "SIGSEGV"
        case .bus: return "SIGBUS"
        case .ill: return "SIGILL"
        case .fpe: return "SIGFPE"
        case .trap: return "SIGTRAP"
        case .other(let value): return "SIGNAL(\(value))"
        }
    }
}

/// Arm64 general-purpose and special registers captured from `ucontext_t`.
///
/// **What:** POD mirror of the register blob written by `CrashRecorder`.
/// **Why:** Analyzer and formatters inspect `pc`/`lr`/`sp`/`fp` without re-reading the binary.
/// **Constraints:** Meaningful only when `CrashArchitecture.arm64` was recorded.
public struct ARM64Registers: Sendable, Equatable {
    /// General-purpose registers `x0` through `x28`.
    public var x: [UInt64]
    /// Frame pointer (`x29`).
    public var fp: UInt64
    /// Link register (`x30`).
    public var lr: UInt64
    /// Stack pointer.
    public var sp: UInt64
    /// Program counter (faulting address for many signals).
    public var pc: UInt64
    /// Current program status register.
    public var cpsr: UInt64

    /// Creates an arm64 register set.
    ///
    /// - Parameters:
    ///   - x: Exactly 29 values for `x0…x28` (shorter arrays are zero-padded; longer truncated).
    ///   - fp: Frame pointer.
    ///   - lr: Link register.
    ///   - sp: Stack pointer.
    ///   - pc: Program counter.
    ///   - cpsr: Status register.
    public init(
        x: [UInt64] = Array(repeating: 0, count: 29),
        fp: UInt64 = 0,
        lr: UInt64 = 0,
        sp: UInt64 = 0,
        pc: UInt64 = 0,
        cpsr: UInt64 = 0
    ) {
        var regs = Array(repeating: UInt64(0), count: 29)
        for i in 0..<min(29, x.count) {
            regs[i] = x[i]
        }
        self.x = regs
        self.fp = fp
        self.lr = lr
        self.sp = sp
        self.pc = pc
        self.cpsr = cpsr
    }
}

/// Mach-O image as stored in the crash dump (crash-time virtual addresses).
///
/// **What:** Base, size, UUID, and path copied from the recorder’s prebuilt image table.
/// **Why:** Absolute addresses from a dead process are only meaningful relative to these ranges
/// because ASLR slides change on the next launch.
/// **Constraints:** Paths may be truncated to `CrashFileFormat.maxPathLength`.
public struct DecodedLoadedImage: Sendable, Equatable {
    /// Crash-time preferred load address (slide applied).
    public var base: UInt64
    /// Approximate mapped size used for range membership tests.
    public var size: UInt64
    /// 16-byte Mach-O UUID (`LC_UUID`), or zeros if unavailable.
    public var uuid: uuid_t
    /// Filesystem path of the image at crash time (may be empty).
    public var path: String

    /// Creates a decoded image record.
    public init(base: UInt64, size: UInt64, uuid: uuid_t, path: String) {
        self.base = base
        self.size = size
        self.uuid = uuid
        self.path = path
    }

    /// Compares images by base, size, UUID bytes, and path.
    public static func == (lhs: DecodedLoadedImage, rhs: DecodedLoadedImage) -> Bool {
        lhs.base == rhs.base
            && lhs.size == rhs.size
            && lhs.path == rhs.path
            && CrashUUID.equal(lhs.uuid, rhs.uuid)
    }

    /// Inclusive-exclusive range `[base, base + size)`.
    public func contains(_ address: UInt64) -> Bool {
        guard size > 0 else { return false }
        return address >= base && address < base &+ size
    }

    /// Offset of `address` from `base`, or `nil` if outside the image.
    public func offset(of address: UInt64) -> UInt64? {
        guard contains(address) else { return nil }
        return address &- base
    }

    /// UUID formatted as a standard 8-4-4-4-12 hex string.
    public var uuidString: String {
        let u = UUID(uuid: uuid)
        return u.uuidString
    }
}

/// Fully decoded crash mini-dump before symbolication / heuristics.
///
/// **What:** Faithful Swift model of the on-disk POD sections.
/// **Why:** Separates binary I/O (`CrashDecoder`) from interpretation (`CrashAnalyzer`).
/// **Constraints:** Addresses and image bases are from the crashed process; do not pass them
/// to `dladdr` without remapping via UUID.
public struct DecodedCrash: Sendable, Equatable {
    /// On-disk format version.
    public var version: UInt32
    /// CPU architecture of the register blob.
    public var architecture: CrashArchitecture
    /// Raw POSIX signal number.
    public var signal: Int32
    /// `siginfo_t.si_code` at crash time.
    public var siCode: Int32
    /// Unix timestamp (seconds) captured near crash time.
    public var timestamp: UInt64
    /// Thread ID recorded by the writer (`pthread_threadid_np` / best effort).
    public var threadID: UInt64
    /// Arm64 registers when `architecture == .arm64`.
    public var registers: ARM64Registers?
    /// Raw return addresses / PCs from frame-pointer unwind (crash-time VAs).
    public var frameAddresses: [UInt64]
    /// Crash-time loaded images.
    public var images: [DecodedLoadedImage]

    /// Creates a decoded crash model.
    public init(
        version: UInt32,
        architecture: CrashArchitecture,
        signal: Int32,
        siCode: Int32,
        timestamp: UInt64,
        threadID: UInt64,
        registers: ARM64Registers?,
        frameAddresses: [UInt64],
        images: [DecodedLoadedImage]
    ) {
        self.version = version
        self.architecture = architecture
        self.signal = signal
        self.siCode = siCode
        self.timestamp = timestamp
        self.threadID = threadID
        self.registers = registers
        self.frameAddresses = frameAddresses
        self.images = images
    }
}

/// A Mach-O image after analysis, suitable for reporting.
///
/// **What:** Same identity as `DecodedLoadedImage`, optionally annotated with whether a matching
/// image is still loaded in the current process (for `dladdr` remapping).
public struct LoadedImage: Sendable, Equatable {
    /// Crash-time load base.
    public var base: UInt64
    /// Crash-time size.
    public var size: UInt64
    /// Mach-O UUID.
    public var uuid: uuid_t
    /// Path from the dump.
    public var path: String
    /// Current-process load base when a same-UUID image is still mapped; otherwise `nil`.
    public var currentBase: UInt64?

    /// Creates an analyzed image record.
    public init(
        base: UInt64,
        size: UInt64,
        uuid: uuid_t,
        path: String,
        currentBase: UInt64? = nil
    ) {
        self.base = base
        self.size = size
        self.uuid = uuid
        self.path = path
        self.currentBase = currentBase
    }

    /// Compares images including optional current remapping base.
    public static func == (lhs: LoadedImage, rhs: LoadedImage) -> Bool {
        lhs.base == rhs.base
            && lhs.size == rhs.size
            && lhs.path == rhs.path
            && lhs.currentBase == rhs.currentBase
            && CrashUUID.equal(lhs.uuid, rhs.uuid)
    }

    /// UUID string for formatters.
    public var uuidString: String {
        UUID(uuid: uuid).uuidString
    }

    /// Last path component, or the full path if empty.
    public var lastPathComponent: String {
        if path.isEmpty { return "(unknown)" }
        return (path as NSString).lastPathComponent
    }
}

/// One stack frame after image/symbol resolution.
///
/// **What:** Crash-time address plus optional owning image and symbol metadata.
/// **Why:** This is the primary unit formatters and higher layers consume.
public struct StackFrame: Sendable, Equatable {
    /// Crash-time virtual address.
    public var address: UInt64
    /// Image that contained the address at crash time, if any.
    public var image: LoadedImage?
    /// Symbol name from `dladdr` after remapping, if resolved.
    public var symbol: String?
    /// Offset from the symbol start when `symbol` is present.
    public var symbolOffset: UInt64?
    /// Offset from the crash-time image base when `image` is present.
    public var imageOffset: UInt64?

    /// Creates a stack frame model.
    public init(
        address: UInt64,
        image: LoadedImage? = nil,
        symbol: String? = nil,
        symbolOffset: UInt64? = nil,
        imageOffset: UInt64? = nil
    ) {
        self.address = address
        self.image = image
        self.symbol = symbol
        self.symbolOffset = symbolOffset
        self.imageOffset = imageOffset
    }
}

/// Lightweight heuristic flags produced by `CrashAnalyzer` (not a full report).
///
/// **What:** Boolean hints derived from registers/images.
/// **Why:** Lets higher layers highlight likely causes without baking prose into the analyzer.
public struct CrashAnalysisFlags: Sendable, Equatable {
    /// `sp` looks unusually low / near null (possible stack corruption or overflow symptom).
    public var possibleStackIssue: Bool
    /// Faulting PC or top frames fall inside Swift runtime images.
    public var involvesSwiftRuntime: Bool
    /// Faulting PC or top frames fall inside UIKit / AppKit style UI frameworks.
    public var involvesUIKitOrAppKit: Bool

    /// Creates analysis flags (defaults all `false`).
    public init(
        possibleStackIssue: Bool = false,
        involvesSwiftRuntime: Bool = false,
        involvesUIKitOrAppKit: Bool = false
    ) {
        self.possibleStackIssue = possibleStackIssue
        self.involvesSwiftRuntime = involvesSwiftRuntime
        self.involvesUIKitOrAppKit = involvesUIKitOrAppKit
    }
}

/// Interpreted crash snapshot ready for formatters and higher-level diagnostics.
///
/// **What:** Named signal, symbolicated frames, images, registers, and heuristic flags.
/// **Why:** Keeps presentation (`CrashTextFormatter` / `CrashMarkdownFormatter`) free of
/// decode/symbolicate logic.
/// **Constraints:** Still does not include app logs, breadcrumbs, or email packaging.
public struct AnalyzedCrash: Sendable, Equatable {
    /// Classified fatal signal.
    public var signal: CrashSignal
    /// `si_code` from the dump.
    public var siCode: Int32
    /// Wall-clock time from the dump when convertible.
    public var timestamp: Date?
    /// Thread ID from the dump.
    public var threadID: UInt64
    /// Registers when architecture was arm64.
    public var registers: ARM64Registers?
    /// Symbolicated / image-attributed frames (PC first when available).
    public var frames: [StackFrame]
    /// Images from the dump with optional current-process remapping bases.
    public var images: [LoadedImage]
    /// Heuristic flags.
    public var flags: CrashAnalysisFlags

    /// Creates an analyzed crash model.
    public init(
        signal: CrashSignal,
        siCode: Int32,
        timestamp: Date?,
        threadID: UInt64,
        registers: ARM64Registers?,
        frames: [StackFrame],
        images: [LoadedImage],
        flags: CrashAnalysisFlags = CrashAnalysisFlags()
    ) {
        self.signal = signal
        self.siCode = siCode
        self.timestamp = timestamp
        self.threadID = threadID
        self.registers = registers
        self.frames = frames
        self.images = images
        self.flags = flags
    }

    /// Plain-text rendering via `CrashTextFormatter`.
    public var textDescription: String {
        CrashTextFormatter.string(from: self)
    }

    /// Markdown rendering via `CrashMarkdownFormatter`.
    public var markdownDescription: String {
        CrashMarkdownFormatter.string(from: self)
    }
}

extension DecodedCrash {
    /// Plain-text rendering of the raw decoded dump (no symbolication).
    public var textDescription: String {
        CrashTextFormatter.string(from: self)
    }

    /// Markdown rendering of the raw decoded dump (no symbolication).
    public var markdownDescription: String {
        CrashMarkdownFormatter.string(from: self)
    }
}
