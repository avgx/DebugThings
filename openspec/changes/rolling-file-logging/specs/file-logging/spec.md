# Spec Delta

## ADDED Requirements

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
