//
//  FileLogHandler.swift
//  swift-logging-extras
//
//  A simple LogHandler that writes log messages to a file
//

import Foundation
import Logging

/// A simple LogHandler that writes log messages to a file
///
/// Useful for test logging where you want to persist output even if the process crashes.
///
/// Example usage with MultiplexLogHandler for dual output:
/// ```swift
/// let fileHandler = try FileLogHandler(label: "test", logFileURL: logFile)
/// let logger = Logger(label: "test") { _ in
///     existingHandler + fileHandler
/// }
/// logger.info("Logged to both console and file")
/// ```
public struct FileLogHandler: LogHandler {
  private let fileHandle: FileHandle
  private let logFileURL: URL
  private let label: String

  public enum FileLogHandlerError: Error {
    case cannotOpenFile(errno: Int32)
  }

  /// Serializes file appends across every handler instance writing to any log file.
  /// Without it, concurrent log calls interleave partial lines in the file (observed
  /// with onvif-probe: two loggers writing the same file corrupted line boundaries).
  /// The line is fully formatted before the lock is taken, so contention is minimal.
  private static let writeLock = NSLock()

  public var metadata: Logger.Metadata = [:]
  public var logLevel: Logger.Level = .info

  /// Create a FileLogHandler that writes to the specified file
  ///
  /// - Parameters:
  ///   - label: The logger label
  ///   - logFileURL: The file URL to write to. Parent directories will be created if needed.
  /// - Throws: If file cannot be created or opened for writing
  public init(label: String, logFileURL: URL) throws {
    self.label = label
    self.logFileURL = logFileURL

    // Create parent directory if needed
    try FileManager.default.createDirectory(
      at: logFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    // Open in O_APPEND mode: every write atomically lands at the file's current
    // end regardless of the file descriptor's offset. This is required because
    // the SwiftLog factory constructs one handler instance per logger label,
    // and loggers are created lazily — with `seekToEndOfFile()` captured once
    // per handle, independently seeked handles on the same path write at stale
    // offsets and overwrite each other's bytes (observed with onvif-probe:
    // three package loggers sharing one log file produced corrupted lines such
    // as "23:23:54:31.213"). O_APPEND also makes the file multi-process safe.
    let descriptor = open(logFileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    guard descriptor >= 0 else {
      throw FileLogHandlerError.cannotOpenFile(errno: errno)
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
    // Format timestamp as readable time
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())

    let levelStr = level.rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)

    var metadataText = ""
    // Add metadata if present - format as key=value pairs
    if let metadata = metadata, !metadata.isEmpty {
      let sortedMetadata = metadata.sorted { $0.key < $1.key }
      let metadataStr = sortedMetadata.map { key, value in
        // Format the value nicely
        let valueStr = "\(value)".replacingOccurrences(of: "\"", with: "")
        return "\(key)=\(valueStr)"
      }.joined(separator: ", ")
      metadataText = " → \(metadataStr)"
    }

    let logLine = "\(timestamp) [\(levelStr)] \(message)\(metadataText)\n"

    guard let data = logLine.data(using: .utf8) else { return }
    // Format fully, then append under one lock so concurrent log calls cannot
    // interleave bytes inside a single line.
    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }
    fileHandle.write(data)
  }
}
