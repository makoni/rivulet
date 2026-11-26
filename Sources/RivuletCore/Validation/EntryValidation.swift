// Ported from Miniflux internal/validator/entry.go and internal/validator/validator.go
// (Apache-2.0); adapted for Swift/SQLite.

/// The rules an entry listing or an entry write fails on.
///
/// The listing block is four rules the reference runs one after another, so the handler calls these
/// four in the order the reference reads them and answers the first rule the input fails on; the order
/// between the four is what the route suite pins, and each rule is pinned here as pure logic. The
/// write block is one function with three rules, so the order between those three is what this file
/// pins.
public enum EntryValidation {
    /// `ValidateEntryStatus`: the two statuses the reference admits.
    public static func validate(status: String) -> EntryValidationRule? {
        status == EntryStatus.read.rawValue || status == EntryStatus.unread.rawValue
            ? nil : .statusInvalid
    }

    /// `ValidateEntryOrder`, restricted to the two columns this port orders by, which is the divergence
    /// `docs/parity.md` records for the reference's nine names.
    public static func validate(order: String) -> EntryValidationRule? {
        order == "published_at" || order == "id" ? nil : .orderInvalid
    }

    /// `ValidateDirection`.
    public static func validate(direction: String) -> EntryValidationRule? {
        direction == "asc" || direction == "desc" ? nil : .directionInvalid
    }

    /// `ValidateRange`, in the reference's order: the offset, the lower bound of the limit, the upper
    /// bound. The first two rules are unreachable through the query read, which answers the default for
    /// a negative value.
    public static func validate(offset: Int, limit: Int) -> EntryValidationRule? {
        if offset < 0 { return .offsetNegative }
        if limit < 0 { return .limitNegative }
        if limit > EntryQuery.maximumLimit { return .limitTooLarge }
        return nil
    }

    /// `ValidateEntriesStatusAndStarredUpdateRequest`: the three rules in the order the reference reads
    /// them, and the first one the input fails on.
    public static func validateStatusAndStarred(entryIDs: [Int], status: String, starred: Bool?)
        -> EntryValidationRule? {
        if entryIDs.isEmpty { return .entryIDsEmpty }
        if status.isEmpty && starred == nil { return .statusOrStarredRequired }
        if !status.isEmpty { return validate(status: status) }
        return nil
    }
}
