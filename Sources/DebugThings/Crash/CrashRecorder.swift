import Darwin
import Foundation
import MachO

/// Installs async-signal-oriented fatal-signal handlers that write a binary crash mini-dump.
///
/// **What:** Opens a pre-truncated capture FD, maintains a Mach-O image snapshot, installs
/// `sigaction` handlers for `SIGABRT`/`SIGSEGV`/`SIGBUS`/`SIGILL`/`SIGFPE`/`SIGTRAP`, and on
/// the next launch promotes a non-empty capture file into a pending `.dtcr` for analysis.
///
/// **Why:** Recording must finish with only async-signal-safe work; decoding, symbolication,
/// logging, and UI belong to later launches / higher layers.
///
/// **Constraints (signal path):** The `@convention(c)` handler must not use Swift heap types
/// (`String`, `Array`, `Data`), Foundation, ARC-heavy APIs, or `backtrace()`. It only fills a
/// static POD buffer and calls `Darwin.write` / `fsync`, then re-raises the signal. This is
/// intentional “C-style Swift”.
public enum CrashRecorder: Sendable {

    /// Serializes install/uninstall against concurrent callers (tests, multi-framework startup).
    private static let installLock = NSLock()

    /// Signals observed by the recorder.
    static let monitoredSignals: [Int32] = [
        SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP,
    ]

    /// Installs handlers and prepares the capture file descriptor.
    ///
    /// **What:** Ensures the crash directory exists, promotes a previous capture into the pending
    /// dump if needed, opens/truncates the capture file, refreshes the image table, and installs
    /// `SA_SIGINFO` handlers.
    ///
    /// **Why:** The FD and image table must exist *before* a crash; the handler cannot `open` or
    /// enumerate dyld safely under a fatal signal.
    ///
    /// **Constraints:** Not async-signal-safe. Call from normal app startup. Repeated calls
    /// uninstall then reinstall.
    ///
    /// - Parameter directory: Directory for crash files. When `nil`, uses Application Support /
    ///   `DebugThings/Crash` (or temporary directory as fallback).
    public static func install(directory: URL? = nil) {
        installLock.lock()
        defer { installLock.unlock() }
        uninstallUnlocked()
        let dir = directory ?? defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CrashRecorderState.directoryPath = dir.path

        promoteCaptureIfNeeded()
        openCaptureFile()
        CrashRecorderImageTable.refresh()
        CrashRecorderImageTable.registerDyldCallbacksIfNeeded()
        installSignalHandlers()
        CrashRecorderState.isInstalled = true
    }

    /// Restores previous signal handlers and closes the capture FD.
    ///
    /// **What:** Uninstalls hooks, closes the capture descriptor, and deletes an empty capture
    /// file after a graceful shutdown.
    ///
    /// **Constraints:** Not async-signal-safe.
    public static func uninstall() {
        installLock.lock()
        defer { installLock.unlock() }
        uninstallUnlocked()
    }

    /// Uninstall implementation assuming `installLock` is already held.
    private static func uninstallUnlocked() {
        guard CrashRecorderState.isInstalled else {
            closeCaptureFile(deleteIfEmpty: false)
            return
        }
        restoreSignalHandlers()
        closeCaptureFile(deleteIfEmpty: true)
        CrashRecorderState.isInstalled = false
    }

    /// Whether a pending `.dtcr` from a previous run is present and large enough to decode.
    public static var hasPendingCrash: Bool {
        guard let url = pendingCrashFileURL else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else {
            return false
        }
        return size.intValue >= CrashFileFormat.minimumValidFileByteCount
    }

    /// URL of the pending crash dump when one exists; otherwise `nil`.
    public static var pendingCrashFileURL: URL? {
        let directory = CrashRecorderState.directoryPath ?? defaultDirectory().path
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(CrashFileFormat.pendingFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Returns the pending crash file URL if a valid dump exists (does not delete it).
    ///
    /// - Returns: Pending file URL, or `nil` when `hasPendingCrash` is false.
    public static func consumePendingCrashFile() -> URL? {
        hasPendingCrash ? pendingCrashFileURL : nil
    }

    /// Deletes the pending crash dump after it has been analyzed or discarded.
    public static func clearPendingCrash() {
        guard let url = pendingCrashFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Default directory for crash files under Application Support.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DebugThings/Crash", isDirectory: true)
    }

    /// Moves a non-empty capture file from the previous run into the pending dump slot.
    private static func promoteCaptureIfNeeded() {
        guard let directory = CrashRecorderState.directoryPath else { return }
        let capture = URL(fileURLWithPath: directory)
            .appendingPathComponent(CrashFileFormat.captureFileName)
        let pending = URL(fileURLWithPath: directory)
            .appendingPathComponent(CrashFileFormat.pendingFileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: capture.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue >= CrashFileFormat.minimumValidFileByteCount
        else {
            try? FileManager.default.removeItem(at: capture)
            return
        }
        try? FileManager.default.removeItem(at: pending)
        try? FileManager.default.moveItem(at: capture, to: pending)
    }

    /// Opens/truncates the capture file and stores the FD for the signal handler.
    private static func openCaptureFile() {
        closeCaptureFile(deleteIfEmpty: false)
        guard let directory = CrashRecorderState.directoryPath else { return }
        let path = (directory as NSString)
            .appendingPathComponent(CrashFileFormat.captureFileName)
        let fd = path.withCString { cPath in
            Darwin.open(cPath, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, 0o644)
        }
        CrashRecorderState.captureFD = fd
    }

    /// Closes the capture FD and optionally removes an empty capture file.
    private static func closeCaptureFile(deleteIfEmpty: Bool) {
        let fd = CrashRecorderState.captureFD
        if fd >= 0 {
            Darwin.close(fd)
            CrashRecorderState.captureFD = -1
        }
        guard deleteIfEmpty, let directory = CrashRecorderState.directoryPath else { return }
        let capture = URL(fileURLWithPath: directory)
            .appendingPathComponent(CrashFileFormat.captureFileName)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: capture.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue == 0
        {
            try? FileManager.default.removeItem(at: capture)
        }
    }

    /// Installs `sigaction` handlers for all monitored signals.
    private static func installSignalHandlers() {
        for (index, signalNumber) in monitoredSignals.enumerated() {
            var action = sigaction()
            memset(&action, 0, MemoryLayout<sigaction>.size)
            action.sa_flags = Int32(SA_SIGINFO | SA_NODEFER)
            sigemptyset(&action.sa_mask)
            action.__sigaction_u.__sa_sigaction = crashSignalHandler

            var previous = sigaction()
            memset(&previous, 0, MemoryLayout<sigaction>.size)
            if sigaction(signalNumber, &action, &previous) == 0 {
                CrashRecorderState.previousActions[index] = previous
                CrashRecorderState.hasPrevious[index] = true
            }
        }
    }

    /// Restores handlers saved by `installSignalHandlers`.
    private static func restoreSignalHandlers() {
        for (index, signalNumber) in monitoredSignals.enumerated() {
            guard CrashRecorderState.hasPrevious[index] else { continue }
            var previous = CrashRecorderState.previousActions[index]
            sigaction(signalNumber, &previous, nil)
            CrashRecorderState.hasPrevious[index] = false
        }
    }
}

// MARK: - Process-wide state

/// Process-wide storage shared by `CrashRecorder` and the C-convention signal handler.
///
/// **Constraints:** Fields read from the handler must remain POD / unsafe buffers — no Swift
/// collections that the handler would touch.
enum CrashRecorderState {
    /// Whether `install` completed successfully.
    nonisolated(unsafe) static var isInstalled = false
    /// Absolute directory path for crash files.
    nonisolated(unsafe) static var directoryPath: String?
    /// Pre-opened capture file descriptor; `-1` when closed.
    nonisolated(unsafe) static var captureFD: Int32 = -1
    /// Saved handlers for restore (index aligned with `monitoredSignals`).
    nonisolated(unsafe) static var previousActions: [sigaction] = .init(
        repeating: sigaction(),
        count: 6
    )
    /// Whether `previousActions[i]` is valid.
    nonisolated(unsafe) static var hasPrevious: [Bool] = .init(repeating: false, count: 6)
    /// Scratch buffer filled by the signal handler then written to `captureFD`.
    nonisolated(unsafe) static let writeBuffer: UnsafeMutableRawPointer = .allocate(
        byteCount: CrashRecorderWriteBuffer.capacity,
        alignment: 8
    )
}

/// Sizing helpers for the static crash write buffer.
enum CrashRecorderWriteBuffer {
    /// Total bytes reserved for one dump serialization attempt.
    static let capacity: Int =
        CrashFileFormat.headerByteCount
        + CrashFileFormat.arm64RegisterByteCount
        + CrashFileFormat.maxFrames * 8
        + CrashFileFormat.maxImages * (8 + 8 + 16 + 4 + 4)
        + CrashFileFormat.maxPathTableBytes
        + 4
}

// MARK: - Image table

/// Handler-visible Mach-O image row.
struct CrashHandlerImage {
    var base: UInt64 = 0
    var size: UInt64 = 0
    var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pathOffset: UInt32 = 0
    var pathLength: UInt32 = 0
}

/// Prebuilt Mach-O image snapshot copied into the dump at crash time.
///
/// **What:** Builds a POD image/path table on the normal path and publishes it for the signal
/// handler to copy. Full enumeration happens only in `refresh()`. Dyld add/remove callbacks
/// update a single row without re-entering dyld enumeration APIs.
///
/// **Constraints:**
/// - Never call `_dyld_image_count` / `_dyld_get_image_header` from an add/remove callback.
/// - Never hold `lock` while calling dyld enumeration (deadlocks against image callbacks).
/// - Never call `refresh` from the signal handler.
enum CrashRecorderImageTable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var didRegisterDyld = false

    /// Number of images published for the handler.
    nonisolated(unsafe) static var handlerCount: Int32 = 0
    /// Image rows for the handler.
    nonisolated(unsafe) static let handlerEntries: UnsafeMutablePointer<CrashHandlerImage> =
        .allocate(capacity: CrashFileFormat.maxImages)
    /// Path bytes for the handler.
    nonisolated(unsafe) static let handlerPaths: UnsafeMutablePointer<UInt8> =
        .allocate(capacity: CrashFileFormat.maxPathTableBytes)
    /// Path byte count published for the handler.
    nonisolated(unsafe) static var handlerPathsCount: Int32 = 0

    /// Registers dyld add/remove callbacks once per process.
    static func registerDyldCallbacksIfNeeded() {
        lock.lock()
        let shouldRegister = !didRegisterDyld
        if shouldRegister {
            didRegisterDyld = true
        }
        lock.unlock()
        guard shouldRegister else { return }

        _dyld_register_func_for_add_image { mh, slide in
            CrashRecorderImageTable.addImage(header: mh, slide: slide)
        }
        _dyld_register_func_for_remove_image { mh, _ in
            CrashRecorderImageTable.removeImage(header: mh)
        }
    }

    /// Rebuilds the entire image table by enumerating dyld (normal path only).
    ///
    /// Builds into temporary buffers **without** holding `lock`, then publishes under the lock
    /// so dyld image callbacks are never blocked on enumeration.
    static func refresh() {
        var localEntries = [CrashHandlerImage]()
        localEntries.reserveCapacity(CrashFileFormat.maxImages)
        var localPaths = [UInt8]()
        localPaths.reserveCapacity(4096)

        let imageCount = Int(_dyld_image_count())
        for index in 0..<imageCount {
            guard localEntries.count < CrashFileFormat.maxImages else { break }
            guard let header = _dyld_get_image_header(UInt32(index)) else { continue }
            let slide = Int64(_dyld_get_image_vmaddr_slide(UInt32(index)))
            let name = _dyld_get_image_name(UInt32(index)).map { String(cString: $0) } ?? ""
            let (uuid, size) = uuidAndSize(header: header, slide: UInt64(bitPattern: slide))
            let pathData = Array(name.utf8.prefix(CrashFileFormat.maxPathLength - 1))
            guard localPaths.count + pathData.count <= CrashFileFormat.maxPathTableBytes else { break }

            let pathOffset = localPaths.count
            localPaths.append(contentsOf: pathData)
            localEntries.append(
                CrashHandlerImage(
                    base: UInt64(UInt(bitPattern: header)),
                    size: size,
                    uuid: uuid,
                    pathOffset: UInt32(pathOffset),
                    pathLength: UInt32(pathData.count)
                )
            )
        }

        lock.lock()
        for i in 0..<localEntries.count {
            handlerEntries[i] = localEntries[i]
        }
        if !localPaths.isEmpty {
            localPaths.withUnsafeBufferPointer { buf in
                handlerPaths.update(from: buf.baseAddress!, count: buf.count)
            }
        }
        handlerPathsCount = Int32(localPaths.count)
        handlerCount = Int32(localEntries.count)
        lock.unlock()
    }

    /// Appends one image using the header pointer from a dyld add-image callback.
    private static func addImage(header: UnsafePointer<mach_header>?, slide: Int) {
        guard let header else { return }
        var info = Dl_info()
        let path: String
        if dladdr(UnsafeRawPointer(header), &info) != 0, let fname = info.dli_fname {
            path = String(cString: fname)
        } else {
            path = ""
        }
        let (uuid, size) = uuidAndSize(header: header, slide: UInt64(bitPattern: Int64(slide)))
        let pathData = Array(path.utf8.prefix(CrashFileFormat.maxPathLength - 1))
        let base = UInt64(UInt(bitPattern: header))

        lock.lock()
        defer { lock.unlock() }
        let count = Int(handlerCount)
        for i in 0..<count {
            if handlerEntries[i].base == base { return }
        }
        guard count < CrashFileFormat.maxImages else { return }
        let pathCount = Int(handlerPathsCount)
        guard pathCount + pathData.count <= CrashFileFormat.maxPathTableBytes else { return }

        for (i, byte) in pathData.enumerated() {
            handlerPaths[pathCount + i] = byte
        }
        handlerEntries[count] = CrashHandlerImage(
            base: base,
            size: size,
            uuid: uuid,
            pathOffset: UInt32(pathCount),
            pathLength: UInt32(pathData.count)
        )
        handlerPathsCount = Int32(pathCount + pathData.count)
        handlerCount = Int32(count + 1)
    }

    /// Removes an image whose load base matches the dyld remove-image header.
    private static func removeImage(header: UnsafePointer<mach_header>?) {
        guard let header else { return }
        let base = UInt64(UInt(bitPattern: header))
        lock.lock()
        defer { lock.unlock() }
        let count = Int(handlerCount)
        guard let index = (0..<count).first(where: { handlerEntries[$0].base == base }) else {
            return
        }
        if index + 1 < count {
            for i in index..<(count - 1) {
                handlerEntries[i] = handlerEntries[i + 1]
            }
        }
        handlerCount = Int32(count - 1)
    }

    /// Extracts `LC_UUID` and an approximate mapping size from a Mach-O header.
    private static func uuidAndSize(
        header: UnsafePointer<mach_header>,
        slide: UInt64
    ) -> (uuid_t, UInt64) {
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var maxExtent: UInt64 = 0
        let is64 = header.pointee.magic == MH_MAGIC_64 || header.pointee.magic == MH_CIGAM_64
        let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        var cmdPtr = UnsafeRawPointer(header).advanced(by: headerSize)
        let ncmds = Int(header.pointee.ncmds)
        let headerAddr = UInt64(UInt(bitPattern: header))
        for _ in 0..<ncmds {
            let cmd = cmdPtr.assumingMemoryBound(to: load_command.self).pointee
            if cmd.cmd == LC_UUID {
                uuid = cmdPtr.assumingMemoryBound(to: uuid_command.self).pointee.uuid
            } else if cmd.cmd == LC_SEGMENT_64 {
                let seg = cmdPtr.assumingMemoryBound(to: segment_command_64.self).pointee
                let end = seg.vmaddr &+ seg.vmsize &+ slide
                if end > headerAddr {
                    maxExtent = max(maxExtent, end &- headerAddr)
                }
            } else if cmd.cmd == UInt32(LC_SEGMENT) {
                let seg = cmdPtr.assumingMemoryBound(to: segment_command.self).pointee
                let end = UInt64(seg.vmaddr) &+ UInt64(seg.vmsize) &+ slide
                if end > headerAddr {
                    maxExtent = max(maxExtent, end &- headerAddr)
                }
            }
            cmdPtr = cmdPtr.advanced(by: Int(cmd.cmdsize))
        }
        if maxExtent == 0 {
            maxExtent = 0x1000_0000
        }
        return (uuid, maxExtent)
    }
}

// MARK: - Frame scratch

/// Static storage for frame addresses captured in the signal handler (avoids malloc).
enum CrashRecorderFrameScratch {
    /// Capacity matches `CrashFileFormat.maxFrames`.
    nonisolated(unsafe) static let addresses: UnsafeMutablePointer<UInt64> =
        .allocate(capacity: CrashFileFormat.maxFrames)
}

// MARK: - Signal handler

/// Fatal-signal entry point installed via `sigaction` / `SA_SIGINFO`.
///
/// **Constraints:** Async-signal-safe subset only. Intentionally written like C.
private let crashSignalHandler: @convention(c) (
    Int32,
    UnsafeMutablePointer<siginfo_t>?,
    UnsafeMutableRawPointer?
) -> Void = { signal, info, context in
    crashHandlerImpl(signal: signal, info: info, context: context)
}

/// Writes little-endian integers into the static crash buffer without allocating.
private struct CrashBufferWriter {
    let base: UnsafeMutableRawPointer
    let capacity: Int
    var cursor: Int = 0

    /// Appends a little-endian `UInt32`.
    mutating func storeUInt32(_ value: UInt32) {
        guard cursor + 4 <= capacity else { return }
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            base.advanced(by: cursor).copyMemory(from: src.baseAddress!, byteCount: 4)
        }
        cursor += 4
    }

    /// Appends a little-endian `Int32`.
    mutating func storeInt32(_ value: Int32) {
        storeUInt32(UInt32(bitPattern: value))
    }

    /// Appends a little-endian `UInt64`.
    mutating func storeUInt64(_ value: UInt64) {
        guard cursor + 8 <= capacity else { return }
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            base.advanced(by: cursor).copyMemory(from: src.baseAddress!, byteCount: 8)
        }
        cursor += 8
    }

    /// Appends raw bytes.
    mutating func storeBytes(_ raw: UnsafeRawPointer, count: Int) {
        guard count > 0, cursor + count <= capacity else { return }
        base.advanced(by: cursor).copyMemory(from: raw, byteCount: count)
        cursor += count
    }
}

/// Implementation of the signal handler body (allocation-free).
private func crashHandlerImpl(
    signal: Int32,
    info: UnsafeMutablePointer<siginfo_t>?,
    context: UnsafeMutableRawPointer?
) {
    let fd = CrashRecorderState.captureFD
    guard fd >= 0 else {
        reraise(signal: signal)
        return
    }

    var writer = CrashBufferWriter(
        base: CrashRecorderState.writeBuffer,
        capacity: CrashRecorderWriteBuffer.capacity
    )

    var pc: UInt64 = 0
    var fp: UInt64 = 0
    var lr: UInt64 = 0
    var sp: UInt64 = 0
    var cpsr: UInt64 = 0

    #if arch(arm64)
    if let context {
        let uc = context.assumingMemoryBound(to: ucontext_t.self)
        let ss = uc.pointee.uc_mcontext.pointee.__ss
        pc = ss.__pc
        fp = ss.__fp
        lr = ss.__lr
        sp = ss.__sp
        cpsr = UInt64(ss.__cpsr)
        withUnsafeBytes(of: ss.__x) { src in
            guard let srcBase = src.baseAddress else { return }
            CrashRecorderGPRScratch.x.withMemoryRebound(to: UInt8.self, capacity: 29 * 8) { dst in
                dst.update(from: srcBase.assumingMemoryBound(to: UInt8.self), count: min(src.count, 29 * 8))
            }
        }
    }
    #endif

    let frameCount = captureFrames(pc: pc, lr: lr, fp: fp)
    let imageCount = min(Int(CrashRecorderImageTable.handlerCount), CrashFileFormat.maxImages)
    let pathCount = min(Int(CrashRecorderImageTable.handlerPathsCount), CrashFileFormat.maxPathTableBytes)
    let siCode = info?.pointee.si_code ?? 0
    let timestamp = UInt64(time(nil))
    var tid: UInt64 = 0
    pthread_threadid_np(nil, &tid)

    writer.storeUInt32(CrashFileFormat.magic)
    writer.storeUInt32(CrashFileFormat.version)
    writer.storeUInt32(CrashFileFormat.archARM64)
    writer.storeUInt32(UInt32(bitPattern: signal))
    writer.storeInt32(siCode)
    writer.storeUInt32(0)
    writer.storeUInt64(timestamp)
    writer.storeUInt64(tid)
    writer.storeUInt32(UInt32(frameCount))
    writer.storeUInt32(UInt32(imageCount))
    writer.storeUInt32(UInt32(pathCount))
    writer.storeUInt32(0)

    for i in 0..<29 {
        writer.storeUInt64(CrashRecorderGPRScratch.x[i])
    }
    writer.storeUInt64(fp)
    writer.storeUInt64(lr)
    writer.storeUInt64(sp)
    writer.storeUInt64(pc)
    writer.storeUInt64(cpsr)

    for i in 0..<frameCount {
        writer.storeUInt64(CrashRecorderFrameScratch.addresses[i])
    }

    for i in 0..<imageCount {
        let image = CrashRecorderImageTable.handlerEntries[i]
        writer.storeUInt64(image.base)
        writer.storeUInt64(image.size)
        withUnsafeBytes(of: image.uuid) { uuidBytes in
            writer.storeBytes(uuidBytes.baseAddress!, count: 16)
        }
        writer.storeUInt32(image.pathOffset)
        writer.storeUInt32(image.pathLength)
    }

    if pathCount > 0 {
        writer.storeBytes(CrashRecorderImageTable.handlerPaths, count: pathCount)
    }

    let payloadCount = writer.cursor
    var sum: UInt32 = 0
    for i in 0..<payloadCount {
        sum &+= UInt32(writer.base.load(fromByteOffset: i, as: UInt8.self))
    }
    writer.storeUInt32(sum)

    if writer.cursor > 0 {
        _ = Darwin.write(fd, writer.base, writer.cursor)
        _ = Darwin.fsync(fd)
    }

    reraise(signal: signal)
}

/// Static GPR scratch used by the signal handler (29 × `UInt64`).
enum CrashRecorderGPRScratch {
    nonisolated(unsafe) static let x: UnsafeMutablePointer<UInt64> = .allocate(capacity: 29)
}

/// Frame-pointer unwind into `CrashRecorderFrameScratch`.
///
/// **Constraints:** Only reads memory; stops on bad pointers. Not a full unwinder.
///
/// - Returns: Number of frames written.
private func captureFrames(pc: UInt64, lr: UInt64, fp: UInt64) -> Int {
    var count = 0

    if count < CrashFileFormat.maxFrames, pc != 0 {
        CrashRecorderFrameScratch.addresses[count] = pc
        count += 1
    }
    if count < CrashFileFormat.maxFrames, lr != 0, lr != pc {
        CrashRecorderFrameScratch.addresses[count] = lr
        count += 1
    }

    #if arch(arm64)
    var frame = fp
    var depth = 0
    while count < CrashFileFormat.maxFrames, depth < CrashFileFormat.maxFrames {
        depth += 1
        guard frame > 0x1000, frame % 8 == 0 else { break }
        guard let framePtr = UnsafePointer<UInt64>(bitPattern: UInt(frame)) else { break }
        let nextFP = framePtr.pointee
        let nextLR = framePtr.advanced(by: 1).pointee
        if nextLR != 0, count < CrashFileFormat.maxFrames {
            CrashRecorderFrameScratch.addresses[count] = nextLR
            count += 1
        }
        if nextFP == 0 || nextFP == frame { break }
        frame = nextFP
    }
    #endif

    return count
}

/// Restores default disposition and re-raises so the system can still produce a crash report.
private func reraise(signal: Int32) {
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}
