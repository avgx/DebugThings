# Spec Delta

## Purpose

Defines how feature code registers diagnostic text, how the UIKit screenshot observer captures that text with the view hierarchy when the user takes a screenshot, and how the hierarchy dump is produced.

## ADDED Requirements

### Requirement: Diagnostics provider registry
`ScreenshotDiagnostics` SHALL run on the main actor. `register(id:provider:)` SHALL store a provider under the id, replacing any provider already stored under that id. `unregister(id:)` SHALL remove the provider for the id when present.

#### Scenario: Replacement
- **WHEN** two providers are registered with the same id
- **THEN** only the most recently registered provider is invoked by `captureAll()`

#### Scenario: Removal
- **WHEN** a provider is unregistered
- **THEN** `captureAll()` no longer includes its output

### Requirement: Diagnostics capture format
`captureAll()` SHALL invoke every registered provider in ascending id order. Each non-empty result SHALL be rendered as `[id]` on one line followed by the body on the next lines. An empty result SHALL be rendered as `[id] (empty)`. Sections SHALL be separated by one blank line. When no provider is registered, the result SHALL be an empty string.

#### Scenario: Nothing registered
- **WHEN** `captureAll()` runs with no providers
- **THEN** the result is an empty string

#### Scenario: Ordered sections
- **WHEN** providers `b` returning `two` and `a` returning an empty string are registered
- **THEN** the result is `[a] (empty)`, a blank line, then `[b]` followed by `two`

### Requirement: Screenshot observation
`ScreenshotObserver.start()` SHALL observe `UIApplication.userDidTakeScreenshotNotification` on the main queue and SHALL do nothing when already started. `stop()` SHALL remove that observation.

#### Scenario: Start is idempotent
- **WHEN** `start()` is called twice
- **THEN** a single screenshot produces a single log entry

#### Scenario: Stop removes observation
- **WHEN** `stop()` is called and then a screenshot is taken
- **THEN** no entry is logged for that screenshot

### Requirement: Screenshot log entry
Each screenshot SHALL produce one `info` log entry through the observer's `Loggable` logger. The entry SHALL contain the screenshot time in ISO 8601 with fractional seconds, the diagnostics section only when the diagnostics are not empty, and the UIKit hierarchy section. The most recent result SHALL be available as `lastCapture`.

#### Scenario: Screenshot with diagnostics
- **WHEN** a screenshot is taken while a provider is registered
- **THEN** the logged entry contains a `Diagnostics:` section followed by a `UIKit hierarchy:` section, and `lastCapture` holds the same diagnostics and hierarchy

#### Scenario: Screenshot without diagnostics
- **WHEN** a screenshot is taken and no provider is registered
- **THEN** the logged entry contains the `UIKit hierarchy:` section and no `Diagnostics:` section

### Requirement: Startup from any actor
`ScreenshotObserver.startFromBootstrap()` SHALL be callable from any thread and SHALL schedule `start()` on the main actor.

#### Scenario: Called off the main thread
- **WHEN** `startFromBootstrap()` is called from a background thread
- **THEN** observation begins on the main actor without blocking the caller

### Requirement: View hierarchy dump
`ViewHierarchyDump.capture()` SHALL describe every connected `UIWindowScene`, sorted by session persistent identifier, with each window's key state, hidden state, window level, and type. It SHALL describe the root view controller tree and the view tree up to depth 6, showing at most 24 visible subviews per view and a count of the rest. When there are no window scenes, it SHALL return `No UIWindowScene`.

#### Scenario: No scenes
- **WHEN** no `UIWindowScene` is connected
- **THEN** `capture()` returns `No UIWindowScene`

#### Scenario: Subview limit
- **WHEN** a view has 30 visible subviews
- **THEN** the dump lists 24 of them and a line stating `+6 more subviews`

### Requirement: Platform availability
The screenshot observer and view hierarchy dump SHALL be compiled only when UIKit is available and the target is neither tvOS nor watchOS. The diagnostics registry SHALL be available wherever the package builds.

#### Scenario: macOS build
- **WHEN** the package is built for macOS without UIKit
- **THEN** `ScreenshotDiagnostics` is available and `ScreenshotObserver` is not
