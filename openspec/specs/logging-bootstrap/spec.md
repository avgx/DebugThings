# logging-bootstrap Specification

## Purpose
Defines how DebugThings installs a single SwiftLog backend per process and how types obtain a stable logger label through the `Loggable` protocol.

## Requirements

### Requirement: Single backend installation per process
The library SHALL allow only one SwiftLog backend installation per process. Every `DebugThings.bootstrap*` function SHALL first claim the installation through `LoggingBootstrap.claimSwiftLogInstall()`. The first claim SHALL succeed and every later claim SHALL return `false`, in which case the bootstrap function SHALL return without calling `LoggingSystem.bootstrap`.

#### Scenario: First bootstrap installs the backend
- **WHEN** `DebugThings.bootstrapStandardOutput()` is called for the first time in a process
- **THEN** `LoggingSystem.bootstrap` is called and the standard-output backend becomes the process backend

#### Scenario: Later bootstrap calls are ignored
- **WHEN** any `DebugThings.bootstrap*` function is called after a backend has already been installed in the process
- **THEN** the call returns without changing the installed backend

#### Scenario: Concurrent claims
- **WHEN** two threads call `claimSwiftLogInstall()` at the same time
- **THEN** exactly one call returns `true`

### Requirement: Standard output bootstrap
`DebugThings.bootstrapStandardOutput(level:metadata:)` SHALL install a `StreamLogHandler.standardOutput` for every logger label. The default level SHALL be `.trace`. When `metadata` is provided, every created handler SHALL start with that metadata.

#### Scenario: Default level
- **WHEN** `bootstrapStandardOutput()` is called without arguments
- **THEN** each logger created afterwards has `logLevel` equal to `.trace`

#### Scenario: Custom level and metadata
- **WHEN** `bootstrapStandardOutput(level: .warning, metadata: ["app": "demo"])` is called
- **THEN** each logger created afterwards has `logLevel` equal to `.warning` and includes the `app` metadata key

### Requirement: Loggable derives a subsystem and logger
A type that conforms to `Loggable` without overriding members SHALL have `subsystem` equal to the lowercased name of the type, and its `logger` SHALL be a `Logger` whose label is that subsystem. Instances SHALL expose the same logger through an instance `logger` property.

#### Scenario: Default subsystem
- **WHEN** a type named `DemoService` conforms to `Loggable` without overriding `subsystem`
- **THEN** `DemoService.subsystem` contains `demoservice`

#### Scenario: Instance access
- **WHEN** an instance of a `Loggable` type reads `logger`
- **THEN** it receives the same logger as the static `logger` property
