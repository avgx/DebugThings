# text-printing Specification

## Purpose
Defines the text helpers for debugging output: pretty JSON and a simplified YAML rendering of any `Encodable` value, and printing the current thread's call stack to standard output.

## Requirements

### Requirement: JSON printing
`JSONPrinter.stringify(_:sortedKeys:)` SHALL encode the value with `JSONEncoder` using pretty printing and without escaping forward slashes. When `sortedKeys` is `true` (default `false`), object keys SHALL be sorted. The result SHALL be returned as a UTF-8 string and encoding errors SHALL be thrown to the caller.

#### Scenario: Slashes are not escaped
- **WHEN** a value containing the string `a/b` is printed
- **THEN** the output contains `a/b` and not `a\/b`

#### Scenario: Sorted keys
- **WHEN** `sortedKeys` is `true` for a value with keys `b` and `a`
- **THEN** the key `a` appears before `b` in the output

#### Scenario: Encoding failure
- **WHEN** the value cannot be encoded
- **THEN** the error from `JSONEncoder` is thrown

### Requirement: Simplified YAML printing
`YAMLPrinter.stringify(_:)` SHALL encode the value to JSON and then render it as YAML-like text. Object keys SHALL be sorted by string order. Nested objects and arrays SHALL be indented by two spaces per level. Strings SHALL be wrapped in double quotes without escaping their contents. Booleans SHALL be rendered as `true` or `false`, numbers as their decimal form, and null as `null`. Array items SHALL start with `- `.

#### Scenario: Sorted keys
- **WHEN** a value with keys `zeta` and `alpha` is printed
- **THEN** `alpha:` appears before `zeta:` in the output

#### Scenario: Nested object
- **WHEN** a value has an object field `inner` containing `x: 1`
- **THEN** the output contains `inner:` followed by a line `  x: 1`

#### Scenario: String values are not escaped
- **WHEN** a string value contains a double quote character
- **THEN** the output keeps that character unescaped inside the surrounding quotes

#### Scenario: Explicit null value
- **WHEN** an `Encodable` value encodes a field with `encodeNil()`
- **THEN** the output renders that field as `null`

#### Scenario: Optional field left nil
- **WHEN** an optional field is `nil` and is encoded with `encodeIfPresent`, which is `JSONEncoder`'s default for optional properties
- **THEN** the field is absent from the output

### Requirement: Current thread stack trace
`Thread.stackTrace()` SHALL print each entry of `Thread.callStackSymbols` for the calling thread to standard output, one entry per line.

#### Scenario: Printing the stack
- **WHEN** `Thread.stackTrace()` is called
- **THEN** each symbol from `Thread.callStackSymbols` is printed on its own line
