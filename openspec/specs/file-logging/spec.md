# file-logging Specification

## Purpose
Defines the plain-text log file backend: where it writes, the line format, how concurrent and multi-handler writes stay intact, and how `bootstrapFile` combines it with the OSLog backend.

## Requirements

### Requirement: File handler creation
`FileLogHandler(label:logFileURL:)` SHALL create the parent directory of the log file when it is missing and SHALL open the file for appending, creating it when absent. If the file cannot be opened, the initializer SHALL throw `FileLogHandlerError.cannotOpenFile` carrying the `errno` value. The default `logLevel` SHALL be `.info` and the default `metadata` SHALL be empty.

#### Scenario: Missing parent directory
- **WHEN** a handler is created for a file whose parent directory does not exist
- **THEN** the directory is created and the file is opened for appending

#### Scenario: Unwritable path
- **WHEN** the file cannot be opened for writing
- **THEN** the initializer throws `FileLogHandlerError.cannotOpenFile` with the `errno` value of the failed open

### Requirement: Line format
Each emitted event SHALL be written as one line terminated by a newline, in the form `HH:mm:ss.SSS [LEVEL] message`. The level SHALL be uppercased and padded to five characters. When the event carries metadata, the line SHALL append ` → ` followed by `key=value` pairs sorted by key and separated by `, `. Double quote characters SHALL be removed from metadata values.

#### Scenario: Message without metadata
- **WHEN** an `info` event with message `started` and no metadata is logged
- **THEN** the written line matches `HH:mm:ss.SSS [INFO ] started` followed by a newline

#### Scenario: Metadata is sorted and quotes are removed
- **WHEN** an `error` event with message `failed` and metadata `{"b": "2", "a": "\"x\""}` is logged
- **THEN** the written line ends with ` → a=x, b=2`

### Requirement: Handler-level metadata is not written
The current implementation SHALL write only the metadata passed with each event. Metadata stored on the handler instance (for example, metadata set by `bootstrapFile(metadata:)`) SHALL NOT appear in the file.

#### Scenario: Base metadata is absent from the file
- **WHEN** a handler whose `metadata` contains `app=demo` logs an `info` event without event metadata
- **THEN** the written line does not contain `app=demo`

### Requirement: Append semantics across handlers
Every write SHALL open the file with `O_APPEND`, so that writes from several handler instances for the same path land at the current end of the file. Writes from all `FileLogHandler` instances in the process SHALL be serialized so that a single line is never interleaved with another line.

#### Scenario: Two handlers on the same file
- **WHEN** handler A writes 20 lines, then handler B is created for the same path and both write interleaved lines
- **THEN** the file contains every line exactly once and no line is overwritten or split

### Requirement: File output through bootstrapFile
`DebugThings.bootstrapFile(level:logFileURL:metadata:subsystem:)` SHALL install a multiplexed backend for every logger label that contains a `FileLogHandler` followed by an `OSLogHandler`, both set to the given level and metadata. The default level SHALL be `.info`. The `subsystem` SHALL default to the main bundle identifier.

#### Scenario: Event reaches both backends
- **WHEN** `bootstrapFile(level: .info, logFileURL: url)` is installed and an `info` message is logged
- **THEN** the message is appended to the file at `url` and is also forwarded to `os.Logger`

#### Scenario: File handler cannot be created
- **WHEN** the file handler for a label cannot be created
- **THEN** that label is still bootstrapped with the OSLog handler only and no error is raised to the caller

### Requirement: Rolling file handler size cap
`RollingFileLogHandler(label:logFileURL:maxFileBytes:)` SHALL keep the active log file at or below `maxFileBytes`, except when a single line on its own is larger than `maxFileBytes`. The default `maxFileBytes` SHALL be 16384. Its initializer SHALL reject a non-positive `maxFileBytes` by a precondition failure.

#### Scenario: Active file stays under the cap
- **WHEN** lines totaling more than `maxFileBytes` are logged through a rolling handler
- **THEN** the active file size after each write is at most `maxFileBytes`

#### Scenario: Oversized single line
- **WHEN** one line is longer than `maxFileBytes`
- **THEN** that line is written whole to the active file after rotation

### Requirement: Rotation to one backup
When a write would make the active file exceed the cap, the handler SHALL copy the active file's current content to `<logFileURL>.1`, replacing any existing backup, and then truncate the active file to zero bytes before writing. The backup SHALL contain only the most recent previous content, so at most two files exist.

#### Scenario: Rotation keeps the previous content
- **WHEN** the active file reaches the cap and the next write triggers rotation
- **THEN** `<logFileURL>.1` contains the content the active file had before rotation, and the active file starts empty and receives the new line

#### Scenario: Older backup is replaced
- **WHEN** rotation happens while `<logFileURL>.1` already exists
- **THEN** the old backup is replaced and no third file is created

### Requirement: Shared file identity across handlers
Every `RollingFileLogHandler` writing to the same path SHALL open the file in append mode, SHALL perform rotation under the same lock used for plain file writes, and SHALL keep writing into the same file after another handler rotated it.

#### Scenario: Two handlers rotate the same file
- **WHEN** two rolling handlers for the same path interleave writes across a rotation
- **THEN** every line appears intact in either the active file or the backup, and no line is written to a file that was already removed

### Requirement: bootstrapFile rolling option
`DebugThings.bootstrapFile` SHALL accept `maxFileBytes: Int? = nil`. When `maxFileBytes` is `nil`, the file half SHALL be a `FileLogHandler` as before. When it is non-nil, the file half SHALL be a `RollingFileLogHandler` with that cap.

#### Scenario: Rolling enabled
- **WHEN** `bootstrapFile(logFileURL: url, maxFileBytes: 16384)` is installed and many lines are logged
- **THEN** `url` stays at or below 16384 bytes and `url.appendingPathExtension("1")` holds the previous content

#### Scenario: Rolling disabled
- **WHEN** `bootstrapFile(logFileURL: url)` is installed
- **THEN** the file grows without rotation, as before
