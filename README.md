# DebugThings

SwiftPM library for SwiftLog-based diagnostics: file logging, OSLog bridging, URL session instrumentation, and a lightweight crash mini-dump recorder/analyzer.

Pulse integration lives in the separate [DebugThingsPulseProxy](https://github.com/avgx/DebugThingsPulseProxy) package.

## Product

| Product | Purpose |
|--------|---------|
| `DebugThings` | SwiftLog bootstraps (`stdout`, `OSLog`, file + OSLog), `LogHandler` helpers, `URLSessionTaskLogger`, crash mini-dump (`CrashRecorder` / `CrashDecoder` / `CrashAnalyzer` / text+Markdown formatters). |

## SwiftPM

```swift
.package(url: "https://github.com/avgx/DebugThings.git", from: "1.0.0")
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "DebugThings", package: "DebugThings"),
    ]
),
```

## Logging bootstrap (SwiftLog)

Call **exactly one** bootstrap per process (subsequent calls are ignored).

```swift
import DebugThings
import Logging

DebugThings.bootstrapStandardOutput(level: .debug)
let log = Logger(label: "app")
log.info("Hello")
```

```swift
DebugThings.bootstrapOSLog(subsystem: "com.example.app", level: .debug)
```

```swift
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("run.log")
DebugThings.bootstrapFile(level: .info, logFileURL: url)
```

### `Loggable`

```swift
import DebugThings
import Logging

enum AccountsService: Loggable {}

AccountsService.logger.info("signed in")
// Uses subsystem derived from the type name.
```

## Crash mini-dump

Records a small binary snapshot on fatal signals (`SIGSEGV`, `SIGABRT`, …), then on the **next** launch decodes/analyzes it. This layer does **not** write to swift-log, build ZIP/email packages, or replace Apple crash reports.

Flow:

1. `CrashRecorder.install()` — pre-open capture FD, cache Mach-O images, install `sigaction` handlers.
2. On crash — handler writes POD registers / FP-unwind addresses / image snapshot (async-signal-safe subset only).
3. Next launch — capture file is promoted to pending `crash.dtcr`.
4. `CrashDecoder` → `DecodedCrash`, `CrashAnalyzer` → `AnalyzedCrash`, then Text/Markdown formatters.

```swift
import DebugThings

CrashRecorder.install()

if CrashRecorder.hasPendingCrash,
   let url = CrashRecorder.consumePendingCrashFile()
{
    let analyzed = try CrashAnalyzer.analyze(contentsOf: url)
    let body = analyzed.textDescription      // or analyzed.markdownDescription
    // hand `body` to your mail / share sheet / server upload
    CrashRecorder.clearPendingCrash()
}
```

**Limits:** the signal handler must not use Swift heap/`String`/`Foundation`. Symbolication uses crash-time image ranges + UUID remapping + `dladdr` on the next launch (ASLR-aware). Not a substitute for KSCrash / MetricKit / Xcode Organizer.

## Tests

```bash
swift test
```

Some tests use a serialized suite so SwiftLog bootstrapping runs only once per test process.
