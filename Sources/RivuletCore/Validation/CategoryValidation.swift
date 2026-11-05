// Ported from Miniflux internal/validator/category.go (Apache-2.0); adapted for Swift/SQLite.

/// The rules a category rename fails on.
///
/// The block runs only when the request carries a title, and the empty check runs before the
/// duplicate read, which is what `CategoryValidationTests` pins. The duplicate answer is handed in
/// as a value, because the storage layer makes it: a rule that read the database could not be
/// pinned as a rule, so `CategoryRepositoryTests` pins the read and the handler pins the answer it
/// writes.
public enum CategoryValidation {
    /// Applies the rules in the reference's order and names the first one the input fails on, or
    /// `nil` when it fails none.
    public static func validate(title: String?, titleIsDuplicate: Bool) -> CategoryValidationRule? {
        guard let title else { return nil }
        if title.isEmpty { return .titleRequired }
        if titleIsDuplicate { return .alreadyExists }
        return nil
    }
}
