# Spec Delta

## MODIFIED Requirements

### Requirement: Handler construction
The handler used for every label SHALL be `OSLogHandler(subsystem:category:)` from the `swift-log-oslog` package. The `DebugThings` module SHALL NOT declare its own `OSLogHandler` type. Initial metadata SHALL be empty, and initial `logLevel` SHALL follow system enablement unless it is assigned explicitly.

#### Scenario: Defaults
- **WHEN** an `OSLogHandler` is created with a subsystem and a category and no level is assigned
- **THEN** its metadata is empty and its `logLevel` is derived from the system's enablement for that category

### Requirement: Message and metadata rendering
Each event SHALL be emitted as one `os.Logger` call. Its text SHALL be the message, then the public metadata, then the private metadata. Each metadata part SHALL be `key=value` pairs sorted by key and separated by spaces. Empty parts SHALL be omitted. The merged metadata SHALL combine handler and event metadata, where event values win on key conflicts.

#### Scenario: Event metadata overrides handler metadata
- **WHEN** the handler has `user=base` with public sensitivity and an event with metadata `user=event` with public sensitivity is logged
- **THEN** the public part of the emitted text ends with `user=event`

#### Scenario: Public and private parts
- **WHEN** an event with `action` tagged public and `user.id` tagged sensitive is logged
- **THEN** the public part contains `action=login` and the private part contains `user.id=12345`

#### Scenario: No metadata
- **WHEN** an event without metadata is logged and the handler has no metadata
- **THEN** the emitted text is the message alone

### Requirement: Bootstrap through bootstrapOSLog
`DebugThings.bootstrapOSLog(level:metadata:subsystem:)` SHALL install an `OSLogHandler` for every logger label, with the category set to the label. The `level` parameter SHALL default to `nil`. The subsystem SHALL default to the main bundle identifier, and SHALL fall back to `default` when none is available.

#### Scenario: Category equals label
- **WHEN** `bootstrapOSLog(subsystem: "com.example.app")` is installed and a logger with label `network` logs
- **THEN** the event is emitted under subsystem `com.example.app` and category `network`

#### Scenario: Missing bundle identifier
- **WHEN** `bootstrapOSLog()` runs without a subsystem and the main bundle has no identifier
- **THEN** the subsystem is `default`

#### Scenario: Level omitted
- **WHEN** `bootstrapOSLog()` is called without `level`
- **THEN** the handler's `logLevel` is not assigned and follows system enablement

#### Scenario: Level given
- **WHEN** `bootstrapOSLog(level: .info)` is called
- **THEN** the handler's `logLevel` is `.info` and overrides system enablement

## REMOVED Requirements

### Requirement: Level mapping
**Reason**: `notice` now maps to `OSLogType.default` instead of `.info`, and the mapping is restated under a new name below.
**Migration**: Read the `OSLogType` mapping from the `Level mapping to OSLogType` requirement.

### Requirement: Privacy of message and metadata
**Reason**: Metadata is no longer always public. Its privacy depends on the `Sensitivity` attribute, and the requirement is restated below.
**Migration**: Tag values with `Sensitivity.public` to keep them visible in Console. Leave them untagged or tag them `.sensitive` to keep them private.

### Requirement: Level filtering is SwiftLog-side
**Reason**: The handler now consults the system's enablement when no explicit level is set, so the old rule no longer holds.
**Migration**: Pass `level:` to `bootstrapOSLog` to keep fixed filtering. Otherwise rely on system enablement.

## ADDED Requirements

### Requirement: Level mapping to OSLogType
The handler SHALL map SwiftLog levels to `OSLogType` as follows: `trace` and `debug` to `.debug`; `info` to `.info`; `notice` and `warning` to `.default`; `error` to `.error`; `critical` to `.fault`.

#### Scenario: Notice is logged at default
- **WHEN** a `notice` event is logged
- **THEN** it is emitted with `OSLogType.default`

#### Scenario: Info is logged at info
- **WHEN** an `info` event is logged
- **THEN** it is emitted with `OSLogType.info`

#### Scenario: Warning is logged at default
- **WHEN** a `warning` event is logged
- **THEN** it is emitted with `OSLogType.default`

#### Scenario: Critical is logged as fault
- **WHEN** a `critical` event is logged
- **THEN** it is emitted with `OSLogType.fault`

### Requirement: Privacy by sensitivity
The message SHALL be interpolated with `privacy: .public`. A metadata value whose `Sensitivity` attribute is `.public` SHALL be interpolated with `privacy: .public`. Every other metadata value SHALL be interpolated with `privacy: .private`, including untagged values, `.sensitive` values, and values with future sensitivity cases.

#### Scenario: Public metadata is visible
- **WHEN** an event with `action` tagged `.public` is logged
- **THEN** the `action` value is emitted with `privacy: .public`

#### Scenario: Untagged metadata is private
- **WHEN** an event with an untagged `client_ip` value is logged
- **THEN** the `client_ip` value is emitted with `privacy: .private`

#### Scenario: Sensitive metadata is private
- **WHEN** an event with `user.id` tagged `.sensitive` is logged
- **THEN** the `user.id` value is emitted with `privacy: .private`

#### Scenario: Message is always public
- **WHEN** any event is logged
- **THEN** its message is emitted with `privacy: .public`

### Requirement: Level derived from system enablement
When no explicit `logLevel` has been assigned, the handler's `logLevel` SHALL be the most verbose level the system has enabled for its category, probing debug, info, default, and error in that order. An explicit assignment of `logLevel` SHALL replace this behavior for the rest of the handler's life.

#### Scenario: Debug enabled
- **WHEN** the system has debug enabled for the category
- **THEN** the derived `logLevel` is `.trace`

#### Scenario: Only default enabled
- **WHEN** the system has only default enabled for the category
- **THEN** the derived `logLevel` is `.notice`

#### Scenario: Explicit override
- **WHEN** `logLevel` is assigned `.critical`
- **THEN** the handler reports `.critical` regardless of system enablement

### Requirement: Injected error fields
When an event carries an error, the handler SHALL add `error.message` and `error.type` to the event's metadata unless the event already sets those keys. Injected fields SHALL be untagged and therefore private.

#### Scenario: Error event
- **WHEN** an `error` event carries an error
- **THEN** `error.message` and `error.type` are added and emitted with `privacy: .private`

#### Scenario: Event sets error.message
- **WHEN** an event carries an error and sets `error.message` itself
- **THEN** the event's own `error.message` is kept and not overwritten
