// Ported from Miniflux internal/validator/entry.go and internal/validator/validator.go
// (Apache-2.0); adapted for Swift/SQLite.

/// The rule an entry listing or an entry write fails on.
///
/// The cases are the reference's plain errors (`internal/validator/entry.go`, and the range block of
/// `internal/validator/validator.go`). The port names the rule rather than the locale string, so the
/// wording an answer writes from it is its own; the reference's message names are in
/// `docs/reference-notes.md`.
public enum EntryValidationRule: String, CaseIterable, Sendable {
    /// `invalid entry status, valid status values are: "read" and "unread"`.
    case statusInvalid

    /// `invalid entry order, valid order values are: …`. The reference's list has nine names; this
    /// port orders by the two columns its schema has, so the rule admits those two, which
    /// `docs/parity.md` records as the divergence.
    case orderInvalid

    /// `invalid direction, valid direction values are: "asc" or "desc"`.
    case directionInvalid

    /// `offset value should be >= 0`. Not reachable through the query read, which answers the default
    /// for a negative value, so `EntryValidationTests` pins this rule as pure logic.
    case offsetNegative

    /// `limit value should be >= 0`, with the same reachability as the offset rule.
    case limitNegative

    /// `limit value should be <= 1000`, the half of the range block the query read can reach.
    case limitTooLarge

    /// `the list of entries cannot be empty`.
    case entryIDsEmpty

    /// `either the status or the starred field must be specified`.
    case statusOrStarredRequired
}
