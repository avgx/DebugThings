# Design

## Context

DebugThings is a SwiftPM library with nine functional areas under `Sources/DebugThings/`: logging bootstrap, file logging, OSLog bridge, custom-format logging, URLSession logging, crash recording, crash analysis, screenshot diagnostics, and text printing. The specs are derived from the source at commit `6d7cd34`. No code is changed.

## Goals / Non-Goals

**Goals**
- One spec per functional area, written as observable behavior with scenarios that could become tests.
- Record current behavior exactly, including limitations, so later changes can use `MODIFIED` against a real baseline.

**Non-Goals**
- Fixing any limitation found while reading the code.
- Specifying internal types, layout of private buffers, or the signal-handler implementation.
- Specifying the `Pulse` integration, which lives in a separate package.

## Decisions

**Flat capability layout.** The project has no existing specs, and the package has one module, so capabilities are top-level kebab-case names (`file-logging`, not `logging/file`). This keeps the path stable when a capability moves between areas.

**Behavior over implementation.** Requirements name the public surface (`bootstrapFile`, `FileLogHandler`, `CrashRecorder.install`) and observable output. Internal helpers such as `mergeMetadata` or `CrashBufferWriter` are not named.

**Known limitations are recorded as current behavior.** The baseline states them as scenarios rather than omitting them, so a future change that fixes one must say so with `MODIFIED`:
- `FileLogHandler` does not write handler-level metadata (`file-logging`, "Handler-level metadata is not written"). `OSLogHandler` and `CustomFormatLogHandler` do merge it.
- `OSLogHandler` marks all metadata as `privacy: .public` and maps `notice` to `.info` (`oslog-logging`).
- `YAMLPrinter` does not escape string contents (`text-printing`).
- `CustomFormatLogHandler` does not sort metadata keys (`custom-format-logging`).

**Signal-handler constraints stay in the design, not the spec.** The crash capture path must not allocate, must use only the file descriptor opened at install time, and must re-raise the signal after writing. These are safety constraints on the implementation. The spec states only the observable result: a dump is written, then the signal is re-raised.

**Platform gating.** `ScreenshotObserver` and `ViewHierarchyDump` compile only with UIKit and outside tvOS/watchOS. `ScreenshotDiagnostics` has no such gate. The spec records this split because it changes what a consumer can import on macOS.

## Risks / Trade-offs

- Scenarios were derived from reading the code, not from running tests. The two swift-log behaviors the specs depend on were checked against swift-log 1.12.0 source (see `tasks.md`), but the specs are not yet pinned by tests.
- Recording a limitation as baseline means the spec currently describes a defect. → Accepted: the alternative is a spec that is wrong about the code.

## Open Questions

- Pin the baseline with tests in a follow-up change: a `FileLogHandler` test that asserts handler-level metadata is absent, and a crash test that raises `SIGABRT` after `install()` and checks that a non-empty capture file remains and the signal is re-raised. These are not part of creating the baseline.
