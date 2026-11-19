# custom-format-logging Specification

## Purpose
Defines the `CustomFormatLogHandler` text format and its fan-out to one or more text output streams, for callers that need a bracketed line format different from the built-in backends.

## Requirements

### Requirement: Handler defaults and output streams
`CustomFormatLogHandler(label:streams:)` SHALL default to a single `StdoutOutputStream`. Its default `logLevel` SHALL be `.debug` and its default `metadata` SHALL be empty. Each formatted line SHALL be written to every configured stream in the order the streams were given.

#### Scenario: Default stream
- **WHEN** a handler is created without `streams`
- **THEN** each formatted line, which already ends with a newline, is printed to standard output exactly once

#### Scenario: Multiple streams
- **WHEN** a handler is created with two streams and an event is logged
- **THEN** the same line is written to both streams in order

### Requirement: Line format
Each event SHALL be formatted as `[yyyy-MM-dd HH:mm:ss.SSS][label][level] message`, followed by a newline. The `level` SHALL be rendered with the SwiftLog level's description.

#### Scenario: Line without metadata
- **WHEN** an `info` event with message `ready` is logged by a handler labeled `net` without metadata
- **THEN** the line matches `[yyyy-MM-dd HH:mm:ss.SSS][net][info] ready` followed by a newline

### Requirement: Metadata rendering
When the merged metadata is not empty, a single space and `key=value` pairs SHALL be inserted between the level and the message, separated by spaces. The merged metadata SHALL combine the handler's metadata with the event's metadata, and event values SHALL win on key conflicts. The pairs SHALL NOT be sorted; their order is the iteration order of the metadata dictionary.

#### Scenario: Event metadata wins
- **WHEN** the handler has `id=1` and the event has `id=2`
- **THEN** the line contains `id=2` and does not contain `id=1`

### Requirement: Timestamp source
The timestamp SHALL be taken from the current local time at the moment the event is formatted, in the device time zone.

#### Scenario: Local time
- **WHEN** an event is logged
- **THEN** the timestamp in the line is the local time at the moment of formatting
