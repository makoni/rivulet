// Ported from Miniflux internal/model/user.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore

/// The document this path writes for an account row.
///
/// The reference writes the 31 fields its struct declares; this port writes the three its schema
/// has columns for, which `docs/parity.md` records. The reference's `Password` field is not written
/// there either, because its tag names nothing. The key order is the order the struct declares,
/// which the pin reads on an input where swapping two of them changes the bytes.
enum RestV1Shape {
    /// `response.JSON(w, r, user)` for the account read.
    static func userDocument(_ user: User) -> JSONValue {
        .object([(key: "id", value: .integer(user.id ?? 0)),
            (key: "username", value: .string(user.username)),
            (key: "is_admin", value: .boolean(user.isAdmin))])
    }
}
