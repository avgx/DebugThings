# Proposal

## Why

DebugThings has no OpenSpec specs yet, so there is no written contract for what the logging bridges, crash recorder, and screenshot helpers do today. Before changing any of them (for example, replacing the local `OSLogHandler` with the Apple `swift-log-oslog` package), we need a baseline that describes the current behavior so later changes can state exactly what they modify.

## What Changes

- Document the current observable behavior of the `DebugThings` library as main specs, derived from the source at commit `6d7cd34`.
- No code changes. Every requirement describes behavior that already exists, including its known limitations (for example, OSLog metadata is always logged as public). Limitations are recorded as-is, not fixed here.
- Create nine capabilities, one per functional area of the package.

## Capabilities

### New Capabilities
- `logging-bootstrap`: One-time SwiftLog backend installation per process, the standard-output bootstrap, and the `Loggable` protocol that derives a logger label from a type.
- `file-logging`: The `FileLogHandler` line format, append semantics, concurrent-write serialization, and the `bootstrapFile` multiplexed setup.
- `oslog-logging`: The `OSLogHandler` bridge to `os.Logger`: level mapping, metadata rendering, privacy behavior, and `bootstrapOSLog`.
- `custom-format-logging`: The `CustomFormatLogHandler` text format and its output streams.
- `url-session-logging`: The `URLSessionTaskLogger` hooks, the SwiftLog-backed implementations, the URLSession delegate forwarder, the `SimpleHttpLogger`, and the cancellation check on `Error`.
- `crash-recording`: The fatal-signal recorder that writes a binary `.dtcr` mini-dump, promotes it on the next launch, and exposes the pending-dump API.
- `crash-analysis`: Decoding `.dtcr` dumps, attributing addresses to images, symbolicating in the current process, and rendering text and Markdown reports.
- `screenshot-diagnostics`: The provider registry for screenshot diagnostics, the UIKit screenshot observer, and the view-hierarchy dump.
- `text-printing`: The JSON and simplified YAML printers for `Encodable` values, and the current-thread stack trace helper.

### Modified Capabilities
- None. The `openspec/specs/` directory is empty, so this change only adds.

## Impact

- Affected code: none. Files under `Sources/DebugThings/` are read, not modified.
- New files: `openspec/specs/<capability>/spec.md` for each capability above, after archive.
- Dependencies: none added. The package keeps `swift-log` `>= 1.12.0` and its current platform minimums.
- Follow-up: the planned `OSLogHandler` migration to `apple/swift-log-oslog` will be a separate change that uses `MODIFIED` requirements on `oslog-logging`.
