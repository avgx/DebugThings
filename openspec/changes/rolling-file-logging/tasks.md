# Tasks

## 1. Shared formatting and lock

- [x] 1.1 Move the line-formatting code in `FileLogHandler` into an internal function that returns the line as `Data`
- [x] 1.2 Make `FileLogHandler.writeLock` internal so the rolling handler uses the same lock

## 2. RollingFileLogHandler

- [x] 2.1 Add `RollingFileLogHandler(label:logFileURL:maxFileBytes:)` with default cap 16384 and a precondition on a positive cap
- [x] 2.2 Before each write, `fstat` the descriptor; if the write would exceed the cap, copy the active file to `<name>.1`, then `ftruncate` to zero
- [x] 2.3 Write the formatted line under the same lock

## 3. Bootstrap

- [x] 3.1 Add `maxFileBytes: Int? = nil` to `bootstrapFile` and choose the handler type from it

## 4. Tests

- [x] 4.1 Test that the active file stays at or below the cap across many lines
- [x] 4.2 Test that the backup holds the previous content and no third file appears
- [x] 4.3 Test two handlers on one path across a rotation: every line is intact
- [x] 4.4 Test that an oversized single line is written whole

## 5. Validate

- [x] 5.1 Run `openspec validate rolling-file-logging --strict`
- [x] 5.2 Run `swift test`
