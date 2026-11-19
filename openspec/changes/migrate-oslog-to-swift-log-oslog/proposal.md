# Proposal

## Why

DebugThings ships its own `OSLogHandler` that sends all metadata to Unified Logging as public, maps `notice` to `.info`, and always logs at the level set by the caller rather than the system's enablement. Apple now publishes `swift-log-oslog` (`OSLogHandler` product) with deny-by-default privacy driven by `Sensitivity`, cached base metadata, system-derived levels, and injected error fields. Maintaining our own bridge duplicates that work, and the local copy is less complete. Adopting the package keeps `bootstrapOSLog` as DebugThings' single-bootstrap entry point and drops the duplicate handler.

## What Changes

- Depend on `apple/swift-log-oslog` and use its `OSLogHandler(subsystem:category:)` inside `bootstrapOSLog` and the OSLog half of `bootstrapFile`.
- Delete `Sources/DebugThings/OSLog/OSLogHandler.swift`.
- **BREAKING**: `DebugThings.OSLogHandler(logger:)` is removed. Callers that build the handler directly must use `OSLogHandler(subsystem:category:)` from `swift-log-oslog`. The package does not accept an `os.Logger`, so a shim that keeps the old initializer cannot be built without also storing the subsystem and category. Released as `3.0.0`, since the latest tag `v2.2.2` is the baseline's source.
- Known direct caller: `DebugThingsPulseProxy/Sources/DebugThingsPulseProxy/bootstrapPulse.swift` builds `OSLogHandler(logger:)` and depends on DebugThings `from: "2.0.0"`. It must move to the new initializer in the same release window, and it needs its own `swift-log-oslog` product dependency.
- **BEHAVIOR**: `bootstrapOSLog(level:)` default changes from `.trace` to `nil`. With `nil`, the handler follows the system's enablement for each category. An explicit `level` still overrides it.
- **BEHAVIOR**: Metadata without `Sensitivity.public` is logged as `privacy: .private`. Messages stay public. This is visible in Console for release builds.
- **BEHAVIOR**: `notice` is logged at `OSLogType.default` instead of `.info`.
- Use the `OSLogHandler` spec changes in `specs/oslog-logging/spec.md` as the contract for these behaviors.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `oslog-logging`: handler construction, level mapping, metadata rendering and privacy, default level and filtering in `bootstrapOSLog`, and error-field injection.

## Impact

- Affected code: `Sources/DebugThings/OSLog/OSLogHandler.swift` (deleted), `Sources/DebugThings/OSLog/bootstrapOSLog.swift`, `Sources/DebugThings/File/bootstrapFile.swift`, `Package.swift`, `Package.resolved`.
- Affected packages: `DebugThingsPulseProxy` (`bootstrapPulse.swift` line 60 uses `OSLogHandler(logger:)`; its `Package.swift` pins DebugThings `from: "2.0.0"`).
- Dependencies: adds `swift-log-oslog` (upstream `from: "0.1.0"`). `Package.swift` moves to `swift-tools-version: 6.2`.
- Consumers outside this repo: the IntercomCore copies under `itv/` and `V6/Env/IntercomCore` define their own `OSLogHandler` struct and do not depend on DebugThings, so they are unaffected. `bootstrapOSLog(level: .debug)` callers such as `OneAccountTests` compile unchanged.
- Out of scope: `FileLogHandler` (its missing handler-metadata behavior is recorded in the baseline, not changed here).
