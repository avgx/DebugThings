# url-session-logging Specification

## Purpose
Defines how DebugThings observes `URLSession` work: the task-logger hook protocol, the SwiftLog-backed logger, the delegate that forwards callbacks, the request and response helper for manual HTTP logging, and the cancellation check for errors.

## Requirements

### Requirement: Task logger hook protocol
`URLSessionTaskLogger` SHALL define five callbacks: task created, task completed with optional error, task finished collecting metrics, task finished decoding with optional error, and data task received data. The protocol SHALL require `Sendable` conformance.

#### Scenario: Custom implementation
- **WHEN** a type implements all five callbacks and conforms to `URLSessionTaskLogger`
- **THEN** it can be passed to `URLSessionTaskLoggerDelegate`

### Requirement: SwiftLog task logger
`SimpleURLSessionTaskLogger(label:logReceiveData:)` SHALL log through a SwiftLog `Logger` with the given label, which defaults to `network`.

#### Scenario: Default label
- **WHEN** `SimpleURLSessionTaskLogger()` is created without arguments
- **THEN** its logger has the label `network`

### Requirement: Task lifecycle messages
The task logger SHALL log task creation as `info`, including the task identifier and the original request URL or `?`. It SHALL log successful completion as `info`, a cancellation as `info`, and any other completion error as `error`. It SHALL log decoding failure as `error` and decoding success as `debug`.

#### Scenario: Cancelled task
- **WHEN** a task completes with an error for which `isCancellation()` is `true`
- **THEN** a `cancelled` message is logged at `info` and no `error` message is logged

#### Scenario: Failed task
- **WHEN** a task completes with a non-cancellation error
- **THEN** a failure message including `localizedDescription` is logged at `error`

### Requirement: Task metrics and received data
The task logger SHALL log collected metrics as `debug`, including the task interval duration in milliseconds with two decimals. It SHALL log received data as `debug` only when `logReceiveData` is `true`.

#### Scenario: Received data is hidden by default
- **WHEN** data is received and `logReceiveData` is `false`
- **THEN** nothing is logged for that callback

### Requirement: No-op task logger
`NoopURLSessionTaskLogger` SHALL implement the protocol with empty callbacks and SHALL produce no output.

#### Scenario: Callbacks do nothing
- **WHEN** any callback is invoked on a `NoopURLSessionTaskLogger`
- **THEN** no logging occurs

### Requirement: Delegate forwarding
`URLSessionTaskLoggerDelegate(taskLogger:)` SHALL forward the `URLSessionTaskDelegate` and `URLSessionDataDelegate` callbacks it implements to the given task logger. When a task is created, it SHALL record a start time for that task. When a task completes, it SHALL discard the recorded start time and any accumulated response data for that task.

#### Scenario: Completion clears per-task state
- **WHEN** `urlSession(_:task:didCompleteWithError:)` is called for a task
- **THEN** the task logger receives `logTask(_:didCompleteWithError:)` and the per-task state for that task is removed

### Requirement: Manual HTTP request and response logging
`SimpleHttpLogger(logger:logBody:)` SHALL log a request as `info` with the method and absolute URL, and each header as `debug`. It SHALL log a response as `info` with the status code, the body size in bytes, and the URL, marked success for status codes 200 through 299 and failure otherwise. It SHALL log errors as `error` with the URL and `localizedDescription`.

#### Scenario: Successful response
- **WHEN** a response with status 204 is logged
- **THEN** an `info` entry includes the status `204`, the body size, and the URL, and is marked as success

#### Scenario: Error
- **WHEN** an error is logged for a URL
- **THEN** an `error` entry includes the URL and the error's `localizedDescription`

### Requirement: Manual HTTP body logging
When `logBody` is `true`, request and response bodies SHALL be logged as `debug`, truncated to their first 500 bytes with `...` appended when longer. When `logBody` is `false`, bodies SHALL NOT be logged.

#### Scenario: Body logging disabled
- **WHEN** `logBody` is `false` and a request with a body is logged
- **THEN** the body is not logged

#### Scenario: Body truncation
- **WHEN** `logBody` is `true` and a response body is 600 bytes long
- **THEN** the logged body contains at most the first 500 bytes followed by `...`

### Requirement: Cancellation check
`Error.isCancellation()` SHALL return `true` when the error is a `CancellationError` or an `NSError` in the `NSURLErrorDomain` with code `NSURLErrorCancelled`, and `false` otherwise.

#### Scenario: URL cancellation
- **WHEN** an error with domain `NSURLErrorDomain` and code `NSURLErrorCancelled` is checked
- **THEN** `isCancellation()` returns `true`

#### Scenario: Other error
- **WHEN** a timeout error is checked
- **THEN** `isCancellation()` returns `false`
