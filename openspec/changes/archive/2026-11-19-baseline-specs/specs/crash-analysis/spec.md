# Spec Delta

## Purpose

Defines how a `.dtcr` crash mini-dump is validated and decoded, how its addresses are attributed to images and symbolicated in the analyzing process, and how the result is rendered as text or Markdown.

## ADDED Requirements

### Requirement: Decoding validation
`CrashDecoder.decode(_:)` and `decode(contentsOf:)` SHALL reject input that is shorter than the minimum valid size, has a checksum that does not match the payload, has a magic word other than the `.dtcr` magic, has a version other than 1, has an unknown architecture, has section counts above the limits, or has a payload that does not end at the checksum. Each rejection SHALL throw the matching `CrashDecodeError` case.

#### Scenario: Truncated file
- **WHEN** the input is shorter than the minimum valid size
- **THEN** `CrashDecodeError.truncated` is thrown

#### Scenario: Corrupted payload
- **WHEN** one payload byte is changed after encoding
- **THEN** `CrashDecodeError.checksumMismatch` is thrown

#### Scenario: Wrong magic
- **WHEN** the first four bytes are not the `.dtcr` magic
- **THEN** `CrashDecodeError.badMagic` is thrown with the value found

### Requirement: Decoded model
A successfully decoded dump SHALL expose the version, architecture, signal number, `si_code`, timestamp, thread identifier, registers (for arm64 dumps), frame addresses, and loaded images with base, size, UUID, and path. Image paths SHALL be read from the path table using the offset and length of each image record.

#### Scenario: Round trip
- **WHEN** a valid arm64 dump is encoded and then decoded
- **THEN** the signal, `si_code`, thread identifier, registers, frame addresses, and image paths are equal to the encoded values

### Requirement: Encoding is limited to arm64
`CrashBinaryEncoder.encode(_:)` SHALL encode only arm64 dumps and SHALL throw `CrashDecodeError.unsupportedArchitecture` for any other architecture.

#### Scenario: Unsupported architecture
- **WHEN** a dump with an architecture other than arm64 is encoded
- **THEN** `CrashDecodeError.unsupportedArchitecture` is thrown

### Requirement: Image attribution
`CrashAnalyzer.analyze(_:)` SHALL attribute each frame address to the dump image whose range `[base, base + size)` contains it, and SHALL record the offset of the address from that image base. Addresses with no containing image SHALL remain unattributed.

#### Scenario: Address inside an image
- **WHEN** a frame address lies inside a dump image
- **THEN** the frame records that image and an image offset equal to the address minus the image base

#### Scenario: Address outside every image
- **WHEN** a frame address lies outside every dump image
- **THEN** the frame has no image and no symbol

### Requirement: Frame list
The analyzed frame list SHALL start with the program counter when registers are present and the first frame address differs from it. Adjacent duplicate addresses SHALL be removed.

#### Scenario: Duplicate adjacent addresses
- **WHEN** the frame addresses are `[A, A, B]`
- **THEN** the analyzed frames are `[A, B]`

### Requirement: Symbolication in the analyzing process
When an image in the dump has the same UUID as an image currently loaded in the analyzing process, the analyzer SHALL remap the address into that loaded image and resolve a symbol name with `dladdr`, recording the symbol offset when available. Otherwise the frame SHALL keep only the image and image offset.

#### Scenario: Same binary still loaded
- **WHEN** the dump image UUID matches a loaded image
- **THEN** the frame has a symbol name when `dladdr` resolves one

#### Scenario: Binary no longer loaded
- **WHEN** no loaded image has the dump image UUID
- **THEN** the frame has an image and image offset and no symbol

### Requirement: Heuristic flags
The analysis SHALL set `possibleStackIssue` when the stack pointer is below `0x10000`. It SHALL set `involvesSwiftRuntime` when one of the first eight frames is in an image whose path contains `libswiftcore`, `libswift`, or `swiftcore`. It SHALL set `involvesUIKitOrAppKit` when one of those frames is in an image whose path contains `uikit`, `appkit`, or `swiftui`. Path matching SHALL be case-insensitive.

#### Scenario: Low stack pointer
- **WHEN** the dump has registers with `sp` equal to `0x1000`
- **THEN** `possibleStackIssue` is `true`

#### Scenario: UIKit frame
- **WHEN** a top frame lies in an image whose path contains `UIKit`
- **THEN** `involvesUIKitOrAppKit` is `true`

### Requirement: Timestamp
The analyzed timestamp SHALL be `nil` when the dump timestamp is zero, and otherwise the Unix time stored in the dump.

#### Scenario: Zero timestamp
- **WHEN** the dump timestamp is `0`
- **THEN** the analyzed timestamp is `nil`

### Requirement: Text report
`CrashTextFormatter.string(from:)` SHALL produce a plain-text report that includes a title line, the signal name, number, and `si_code`, the time in ISO 8601 or `(unknown)`, the thread identifier, the flags, the faulting frame, the registers when present, the stack (or `(no frames)`), and the image count with up to the first 64 images. The decoded-model overload SHALL produce the same report using raw addresses without symbol names.

#### Scenario: Report without frames
- **WHEN** an analyzed crash has no frames
- **THEN** the stack section contains `(no frames)`

### Requirement: Markdown report
`CrashMarkdownFormatter` SHALL render the same analyzed and decoded content as a Markdown document.

#### Scenario: Markdown output
- **WHEN** an analyzed crash is rendered with `CrashMarkdownFormatter`
- **THEN** the result is a Markdown string that includes the signal name
