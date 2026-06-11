# DebugThings

SwiftPM library for SwiftLog-based diagnostics: file logging, OSLog bridging, and URL session instrumentation.

Pulse integration lives in the separate [DebugThingsPulseProxy](https://github.com/avgx/DebugThingsPulseProxy) package.

## Product

| Product | Purpose |
|--------|---------|
| `DebugThings` | SwiftLog bootstraps (`stdout`, `OSLog`, file + OSLog), `LogHandler` helpers, `URLSessionTaskLogger`, `URLSessionTaskLoggerDelegate`. |

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

## Tests

```bash
swift test
```

Some tests use a serialized suite so SwiftLog bootstrapping runs only once per test process.
