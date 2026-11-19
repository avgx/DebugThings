# Spec Delta

## Purpose

Defines the SwiftLog-to-unified-logging bridge: how levels map to `OSLogType`, how metadata is rendered into the message, what privacy level is applied, and how `bootstrapOSLog` installs it.

## ADDED Requirements

### Requirement: Handler construction
`OSLogHandler(logger:)` SHALL wrap the given `os.Logger`. The handler's initial `logLevel` SHALL be `.trace`, and its initial metadata SHALL be empty.

#### Scenario: Defaults
- **WHEN** an `OSLogHandler` is created with an `os.Logger`
- **THEN** `logLevel` is `.trace` and `metadata` is empty

### Requirement: Level mapping
The handler SHALL map SwiftLog levels to `OSLogType` as follows: `trace` and `debug` to `.debug`; `info` and `notice` to `.info`; `warning` to `.default`; `error` to `.error`; `critical` to `.fault`.

#### Scenario: Notice is logged at info
- **WHEN** a `notice` event is logged
- **THEN** it is emitted with `OSLogType.info`

#### Scenario: Warning is logged at default
- **WHEN** a `warning` event is logged
- **THEN** it is emitted with `OSLogType.default`

#### Scenario: Critical is logged as fault
- **WHEN** a `critical` event is logged
- **THEN** it is emitted with `OSLogType.fault`

### Requirement: Message and metadata rendering
Each event SHALL be emitted as one `os.Logger` call whose text is the message followed by ` | ` and the merged metadata. The merged metadata SHALL combine the handler's metadata with the event's metadata, where event values win on key conflicts. Entries SHALL be rendered as `key=value` pairs sorted by key and separated by spaces. When the merged metadata is empty, no ` | ` suffix SHALL be added.

#### Scenario: Event metadata overrides handler metadata
- **WHEN** the handler has `user=base` and an event with metadata `user=event` is logged
- **THEN** the emitted text ends with ` | user=event`

#### Scenario: No metadata
- **WHEN** an event without metadata is logged and the handler has no metadata
- **THEN** the emitted text is the message alone

### Requirement: Privacy of message and metadata
The message and the metadata suffix SHALL both be interpolated with `privacy: .public`. The handler SHALL NOT redact any metadata value based on its origin or type.

#### Scenario: Metadata is public
- **WHEN** an event with metadata `token=secret` is logged
- **THEN** the emitted interpolation is marked public and the value `secret` is not redacted by the handler

### Requirement: Bootstrap through bootstrapOSLog
`DebugThings.bootstrapOSLog(level:metadata:subsystem:)` SHALL install an `OSLogHandler` for every logger label, using a `os.Logger` whose category is the label. The default level SHALL be `.trace`. The subsystem SHALL default to the main bundle identifier, and SHALL fall back to `default` when no bundle identifier is available.

#### Scenario: Category equals label
- **WHEN** `bootstrapOSLog(subsystem: "com.example.app")` is installed and a logger with label `network` logs
- **THEN** the event is emitted under subsystem `com.example.app` and category `network`

#### Scenario: Missing bundle identifier
- **WHEN** `bootstrapOSLog()` runs without a subsystem and the main bundle has no identifier
- **THEN** the subsystem is `default`

### Requirement: Level filtering is SwiftLog-side
The handler SHALL NOT consult the system's unified-logging enablement. Filtering SHALL come only from the `logLevel` value set on the handler, which `bootstrapOSLog` sets from its `level` argument.

#### Scenario: Level from bootstrap
- **WHEN** `bootstrapOSLog(level: .info)` is installed and a `debug` event is logged through a logger whose level is `.info`
- **THEN** the event is dropped by SwiftLog before reaching the handler
