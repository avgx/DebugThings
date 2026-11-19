# Design

## Context

`Sources/DebugThings/OSLog/OSLogHandler.swift` (released in `v2.2.2`) is a hand-written SwiftLog-to-`os.Logger` bridge. It is public and constructed as `OSLogHandler(logger:)`. `bootstrapOSLog` and the OSLog half of `bootstrapFile` both use it. `DebugThingsPulseProxy` also constructs it directly.

Apple's `apple/swift-log-oslog` (product `OSLogHandler`, module `OSLogHandler`) provides a sensitivity-aware handler with the same bridging job. The baseline spec `oslog-logging` describes the current handler.

## Goals / Non-Goals

**Goals**
- Use Apple's handler for all OSLog output from DebugThings, and delete the duplicate.
- Keep `bootstrapOSLog` as the single-bootstrap entry point, because `LoggingBootstrap` is DebugThings policy, not part of the Apple package.
- Describe each behavior change in the `oslog-logging` delta, so the release notes can be written from the spec.

**Non-Goals**
- Changing `FileLogHandler`, `CustomFormatLogHandler`, or the crash and screenshot code.
- Adding `Sensitivity` tagging to DebugThings' own call sites. That is a separate decision for each caller.
- Keeping `OSLogHandler(logger:)` alive. See the decision below.

## Decisions

**Adopt the package handler, delete the local one.** The package covers everything the local bridge does and more: deny-by-default privacy, cached base metadata, system-derived levels, error fields, and benchmarks. Keeping a second implementation would drift.

**Remove `OSLogHandler(logger:)` instead of shimming it.** The package initializer takes `subsystem` and `category`. `os.Logger` does not expose those, so a shim would have to store them separately from the `os.Logger` the caller passed. The cleaner break is a major version.

**`bootstrapOSLog(level:)` defaults to `nil`.** With `nil`, the handler does not assign `logLevel`, so the package derives the level from system enablement. Callers that pass `level:` keep the same fixed filtering as before. Source compatibility is preserved for callers that pass a level.

**`bootstrapFile` keeps its explicit level.** Its OSLog half still assigns `logLevel` from its `level` argument (default `.info`). This keeps the file and OSLog halves filtered the same way. The alternative is in Open Questions.

**Privacy follows the package's rules, unchanged.** Untagged and `.sensitive` metadata become `privacy: .private`. The message stays public. DebugThings does not add a wrapper that tags everything public. A wrapper would undo the privacy default for every caller of `bootstrapOSLog`.

**Tools version is 6.2.** Upstream declares `swift-tools-version: 6.2`. DebugThings moves to 6.2 in the same change, so the manifest matches the compiler the dependency requires.

**swift-log lower bound is 1.13.2.** `swift-log-oslog` 0.1.0 declares `from: "1.6.0"`, but `Logger.MetadataValueAttributes` first ships in swift-log 1.13.2. The resolved pin must be at least that, or `SensitivityAttribute` does not compile.

## Risks / Trade-offs

- Console output for untagged metadata changes from readable to `<private>` in release builds. Callers that relied on it must tag values `Sensitivity.public` or move them into the message. → Documented in the release notes and in the delta.
- `notice` moves from `.info` to `.default`, so it now appears in `log stream` without `--level info`. → Documented.
- The package's own test suite covers the level mapping, so DebugThings tests should check only that DebugThings wires the handler correctly. → See tasks.

## Decisions recorded after review

- **Privacy.** `bootstrapOSLog` accepts deny-by-default. It does not tag metadata public.
- **`bootstrapFile` level stays explicit.** The other option is to leave the OSLog half's `logLevel` unset, so Console follows `OSLog.isEnabled` while the file half stays at `level`. Those two backends would then drop different events. The explicit assignment keeps one threshold for both.
- **Release.** Ship DebugThings `3.0.0` and update `DebugThingsPulseProxy` in the same window.
