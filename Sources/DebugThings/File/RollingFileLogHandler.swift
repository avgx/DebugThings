//
//  RollingFileLogHandler.swift
//  DebugThings
//
//  A LogHandler that writes to a file and keeps the file under a size cap.
//

import Foundation
import Logging

/// A LogHandler that writes to a file and keeps the active file at or below a size cap.
///
/// When a write would push the active file past `maxFileBytes`, the handler copies the
/// current content to `<logFileURL>.1` (replacing the previous backup) and truncates the
/// active file to zero. The active file keeps its inode, so every handler opened on the
/// same path keeps appending to it. At most two files exist.
///
/// Rotation is serialized with ``FileLogHandler/writeLock``, so rolling and plain handlers
/// on the same path do not interleave. The lock is per process; two processes writing the
/// same file can race a rotation.
///
/// Do not log through this handler from signal handlers: rotation allocates and uses Foundation.
///
/// Example:
/// ```swift
/// let handler = try RollingFileLogHandler(label: "app", logFileURL: url, maxFileBytes: 16 * 1024)
/// ```
public struct RollingFileLogHandler: LogHandler {
  /// Default cap: 16 KiB per file.
  public static let defaultMaxFileBytes = 16 * 1024

  private let fileHandle: FileHandle
  private let logFileURL: URL
  private let backupURL: URL
  private let label: String
  private let maxFileBytes: Int

  public var metadata: Logger.Metadata = [:]
  public var logLevel: Logger.Level = .info

  /// Create a RollingFileLogHandler that writes to the specified file.
  ///
  /// - Parameters:
  ///   - label: The logger label
  ///   - logFileURL: The active log file. Parent directories will be created if needed.
  ///   - maxFileBytes: Soft cap for the active file. A single line larger than this is written whole.
  /// - Throws: If the file cannot be opened for writing
  public init(
    label: String,
    logFileURL: URL,
    maxFileBytes: Int = RollingFileLogHandler.defaultMaxFileBytes
  ) throws {
    precondition(maxFileBytes > 0, "maxFileBytes must be positive")
    self.label = label
    self.logFileURL = logFileURL
    self.backupURL = logFileURL.appendingPathExtension("1")
    self.maxFileBytes = maxFileBytes

    try FileManager.default.createDirectory(
      at: logFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    // O_APPEND for the same reason as FileLogHandler: every handler on this path, and every
    // rotation, writes at the file's current end. O_RDWR (not O_WRONLY) because rotation
    // reads the active file back through this descriptor before truncating it.
    let descriptor = open(logFileURL.path, O_RDWR | O_CREAT | O_APPEND, 0o644)
    guard descriptor >= 0 else {
      throw FileLogHandler.FileLogHandlerError.cannotOpenFile(errno: errno)
    }
    self.fileHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  public func log(event: LogEvent) {
    log(
      level: event.level,
      message: event.message,
      metadata: event.metadata,
      source: event.source,
      file: event.file,
      function: event.function,
      line: event.line
    )
  }

  public func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    guard let data = FileLogHandler.formatLine(level: level, message: message, metadata: metadata) else { return }
    FileLogHandler.writeLock.lock()
    defer { FileLogHandler.writeLock.unlock() }
    rotateIfNeeded(incomingBytes: data.count)
    fileHandle.write(data)
  }

  /// Rotates the active file if appending `incomingBytes` would exceed the cap.
  /// Must be called with ``FileLogHandler/writeLock`` held.
  private func rotateIfNeeded(incomingBytes: Int) {
    let descriptor = fileHandle.fileDescriptor
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { return }
    let size = Int(info.st_size)

    // An empty file is never rotated, so a single oversized line is written whole.
    guard size > 0, size + incomingBytes > maxFileBytes else { return }

    // Copy the current content to the backup. If the copy fails, the active file is still
    // truncated so the cap holds; the previous backup content is then lost.
    let content = Self.readAll(descriptor: descriptor, count: size) ?? Data()
    try? content.write(to: backupURL, options: .atomic)

    // Truncate in place. Other handlers keep their O_APPEND descriptors on this inode, so
    // their next write lands at offset 0.
    _ = ftruncate(descriptor, 0)
  }

  private static func readAll(descriptor: Int32, count: Int) -> Data? {
    var buffer = Data(count: count)
    let bytesRead = buffer.withUnsafeMutableBytes { raw -> Int in
      pread(descriptor, raw.baseAddress, count, 0)
    }
    guard bytesRead == count else { return nil }
    return buffer
  }
}
