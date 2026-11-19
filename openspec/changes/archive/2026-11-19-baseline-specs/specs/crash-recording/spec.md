# Spec Delta

## Purpose

Defines the fatal-signal recorder that writes a binary mini-dump of the crashing process, promotes that dump on the next launch, and exposes the pending-dump API that callers use to read and clear it.

## ADDED Requirements

### Requirement: Installing the recorder
`CrashRecorder.install(directory:)` SHALL create the crash directory if it is missing, SHALL default that directory to `DebugThings/Crash` under Application Support (falling back to the temporary directory), and SHALL install handlers for `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, and `SIGTRAP`. Calling `install` again SHALL first uninstall the current handlers and then install them again.

#### Scenario: Default directory
- **WHEN** `install()` is called without a directory
- **THEN** the recorder uses `DebugThings/Crash` under Application Support

#### Scenario: Reinstall
- **WHEN** `install()` is called while the recorder is already installed
- **THEN** the previous handlers are restored and the new handlers are installed, and `isInstalled` remains `true`

### Requirement: Capture on fatal signal
When a monitored signal is raised while the recorder is installed, the recorder SHALL write one dump to the pre-opened capture file, flush it to disk, restore the default signal disposition, and re-raise the signal so the system can still produce its normal crash report. The dump SHALL contain the signal number, the `si_code`, the Unix timestamp, the thread identifier, the frame addresses, the Mach-O image table, and a trailing checksum.

#### Scenario: Crash after install
- **WHEN** the process raises `SIGSEGV` after `install()` succeeded
- **THEN** a non-empty capture file is written before the process terminates, and the signal is re-raised with the default handler

#### Scenario: Signal without an open capture file
- **WHEN** a monitored signal arrives and no capture file descriptor is open
- **THEN** the signal is re-raised without writing a dump

### Requirement: Dump limits
A dump SHALL contain at most 64 frame addresses, at most 128 image records, and at most 16 KiB of image path bytes. Each image path SHALL be truncated to 1024 bytes.

#### Scenario: Many images
- **WHEN** more than 128 images are loaded at crash time
- **THEN** the dump contains exactly the first 128 image records

### Requirement: Promotion on next launch
On the next `install()`, a capture file from the previous run that is at least the minimum valid size SHALL replace any existing pending dump and be renamed to `crash.dtcr`. A capture file smaller than the minimum valid size SHALL be deleted.

#### Scenario: Crash in previous run
- **WHEN** a non-empty `crash.capture.dtcr` exists and `install()` is called
- **THEN** the file becomes `crash.dtcr` and the capture file no longer exists

#### Scenario: Empty capture from a clean exit
- **WHEN** a zero-length capture file exists and `install()` is called
- **THEN** the capture file is deleted and no pending dump is created

### Requirement: Pending dump API
`hasPendingCrash` SHALL be `true` only when `crash.dtcr` exists and is at least the minimum valid size. `pendingCrashFileURL` SHALL return the URL of `crash.dtcr` when the file exists and `nil` otherwise. `consumePendingCrashFile()` SHALL return that URL when `hasPendingCrash` is `true` and SHALL NOT delete the file. `clearPendingCrash()` SHALL delete `crash.dtcr` when it exists.

#### Scenario: Read without delete
- **WHEN** `consumePendingCrashFile()` returns a URL
- **THEN** the file still exists until `clearPendingCrash()` is called

#### Scenario: No pending dump
- **WHEN** no `crash.dtcr` exists
- **THEN** `hasPendingCrash` is `false` and `consumePendingCrashFile()` returns `nil`

### Requirement: Uninstall
`CrashRecorder.uninstall()` SHALL restore the signal handlers that were in place before `install()`, close the capture file, and delete the capture file if it is empty. `isInstalled` SHALL be `false` after `uninstall()`.

#### Scenario: Clean shutdown
- **WHEN** `uninstall()` is called after `install()` and no crash occurred
- **THEN** the previous signal handlers are restored and no empty capture file remains

### Requirement: Process-local installed state
`isInstalled` SHALL report whether the current process has the recorder installed. It SHALL NOT be persisted across launches.

#### Scenario: New launch
- **WHEN** a new process starts without calling `install()`
- **THEN** `isInstalled` is `false`
