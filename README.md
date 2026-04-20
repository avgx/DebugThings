# DebugThings

SwiftPM libraries for SwiftLog-based diagnostics, optional file logging, OSLog bridging, URL session instrumentation, and optional [Pulse](https://github.com/kean/Pulse) integration.

## Products

| Product | Purpose |
|--------|---------|
| `DebugThings` | SwiftLog bootstraps (`stdout`, `OSLog`, file + OSLog), `LogHandler` helpers, `URLSessionTaskLogger`, `NetworkLoggingDelegate`. |
| `DebugThingsPulseProxy` | Pulse `LoggerStore` log handler, `NetworkLogger` capture settings from app UI, `PulseSessionEventLogger`, streaming body skip helper. |

Add only `DebugThings` if you do not want a Pulse dependency.

## SwiftPM

```swift
.package(path: "../DebugThings")
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "DebugThings", package: "DebugThings"),
        .product(name: "DebugThingsPulseProxy", package: "DebugThings"),
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

## Pulse (optional)

```swift
import DebugThings
import DebugThingsPulseProxy
import Logging

DebugThings.bootstrapPulse(level: .trace)
```

Update capture rules when your settings UI changes:

```swift
var settings = PulseNetworkCaptureSettings.default
settings.excludedHosts = ["telemetry.example.com", "stream.example.com"]
settings.includedHosts = ["api.example.com"]
settings.applyToSharedNetworkLogger()
```

Wire URL session delegates:

```swift
let pulse = PulseSessionEventLogger()
let taskLogger = StreamingSkippingURLSessionTaskLogger(inner: pulse)
let delegate = NetworkLoggingDelegate(taskLogger: taskLogger)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

`StreamingSkippingURLSessionTaskLogger` stops forwarding response bodies to Pulse once the response looks like SSE (`text/event-stream`) or MJPEG-style multipart (`multipart/x-mixed-replace`). Combine with `excludedHosts` / `excludedURLs` for endpoints that never get a useful `Content-Type`.

## Tests

```bash
swift test
```

Some tests use a serialized suite so SwiftLog bootstrapping runs only once per test process.
