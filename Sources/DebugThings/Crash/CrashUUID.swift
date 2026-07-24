import Darwin
import Foundation

/// Helpers for comparing Darwin `uuid_t` values (not `Equatable` by default).
///
/// **What:** Byte-wise UUID comparison used by image models.
/// **Why:** `uuid_t` is a tuple and does not synthesize `Equatable` in a way Swift always accepts.
enum CrashUUID {
    /// Byte-wise equality for Mach-O UUIDs.
    static func equal(_ lhs: uuid_t, _ rhs: uuid_t) -> Bool {
        withUnsafeBytes(of: lhs) { left in
            withUnsafeBytes(of: rhs) { right in
                memcmp(left.baseAddress, right.baseAddress, 16) == 0
            }
        }
    }
}
