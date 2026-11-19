# Tasks

## 1. Dependency and toolchain

- [x] 1.1 Add `.package(url: "https://github.com/apple/swift-log-oslog", from: "0.1.0")` to `Package.swift` and the `OSLogHandler` product to the `DebugThings` target
- [x] 1.2 Set `swift-tools-version` to 6.2 and resolve on that toolchain
- [x] 1.3 Confirm `Package.resolved` pins `swift-log-oslog` and a `swift-log` version that satisfies it

## 2. Replace the handler

- [x] 2.1 Delete `Sources/DebugThings/OSLog/OSLogHandler.swift`
- [x] 2.2 In `bootstrapOSLog`, change `level` to `Logging.Logger.Level? = nil`. Create `OSLogHandler(subsystem:category:)` with the resolved subsystem and the label as category. Assign `logLevel` only when `level` is non-nil. Assign `metadata` when provided
- [x] 2.3 In `bootstrapFile`, create the OSLog half with `OSLogHandler(subsystem:category:)`. Keep the explicit `logLevel` assignment and the metadata assignment
- [x] 2.4 Add `import OSLogHandler` to every file that now uses the package handler

## 3. Tests

- [x] 3.1 Add a test that assigns `logLevel` on the package handler and reads the same value back, to confirm DebugThings does not depend on system enablement when a level is set
- [x] 3.2 Add a smoke test that calls `bootstrapOSLog()` without `level` and logs one event, to confirm the default path does not crash
- [x] 3.3 Keep the existing `bootstrapFile` test passing

## 4. Consumers

- [x] 4.1 Confirm by search that no other code in this workspace calls `DebugThings.OSLogHandler(logger:)`. Search result so far: only `DebugThingsPulseProxy/.../bootstrapPulse.swift`
- [x] 4.2 In `DebugThingsPulseProxy`, change `bootstrapPulse.swift` to `OSLogHandler(subsystem:category:)`, add the `swift-log-oslog` product dependency, and release that package after `3.0.0` is tagged. This is a separate repository and may need its own change

## 5. Validate and release

- [x] 5.1 Run `openspec validate migrate-oslog-to-swift-log-oslog --strict`
- [x] 5.2 Run `swift build` and `swift test` on macOS
- [x] 5.3 Tag `3.0.0` only after 5.2 passes and the open questions in `design.md` are answered
