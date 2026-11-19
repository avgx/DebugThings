# Tasks

## 1. Validate the baseline specs

- [x] 1.1 Write `specs/<capability>/spec.md` for each of the nine capabilities listed in `proposal.md`
- [x] 1.2 Run `openspec validate baseline-specs --strict` and fix every reported issue
- [x] 1.3 Confirm each `## Purpose` is at least 50 characters (checked by the strict validation)

## 2. Check the scenarios against the code

- [x] 2.1 Confirm `SwiftLog` drops events below `logLevel` before they reach `OSLogHandler` (`oslog-logging`, "Level filtering is SwiftLog-side"). Checked against swift-log 1.12.0: `Logger.logLevel` forwards to `handler.logLevel`, and `_log` filters on it
- [x] 2.2 Confirm `FileLogHandler` drops handler-level metadata (`file-logging`, "Handler-level metadata is not written"). Checked against swift-log 1.12.0: `Logger` passes only `event.metadata` to `handler.log(event:)`, and `handler.metadata` is read only by the `Logger.metadata` getter
