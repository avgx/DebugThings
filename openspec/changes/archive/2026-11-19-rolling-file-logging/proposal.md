# Proposal

## Why

`FileLogHandler` appends to one file without a size limit. A long-running app grows that file without bound, and a file-only view of the last minutes before a crash is lost once it grows. A bounded file that keeps the most recent output is enough to answer "how did the last session end" without a logging backend.

## What Changes

- Add `RollingFileLogHandler`, a file backend that caps the active file at a configurable size. When a write would exceed the cap, the current file is copied to `<name>.1` (replacing the previous `.1`) and the active file is truncated to zero, so every handler keeps appending to the same inode.
- `bootstrapFile` gains an optional `maxFileBytes`. When it is set, the file half uses `RollingFileLogHandler`. When it is `nil`, behavior is unchanged.
- Default cap when rolling is enabled: 16 KiB. At most two files exist: `<name>` and `<name>.1`.
- No change to the line format, level filtering, or OSLog half.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `file-logging`: adds rolling behavior. Existing requirements are unchanged.

## Impact

- New file: `Sources/DebugThings/File/RollingFileLogHandler.swift`.
- `Sources/DebugThings/File/FileLogHandler.swift`: the line-formatting code moves into a shared internal function, and its write lock becomes internal so both handlers serialize writes to the same path.
- `Sources/DebugThings/File/bootstrapFile.swift`: new optional parameter.
- Tests added in `Tests/DebugThingsTests/`.
- No new dependencies. Not a breaking change.
