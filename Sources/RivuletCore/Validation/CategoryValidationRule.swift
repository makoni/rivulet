// Ported from Miniflux internal/validator/category.go (Apache-2.0); adapted for Swift/SQLite.

/// The rule a category rename fails on.
///
/// The cases are the reference's two localized errors (`internal/validator/category.go` at commit
/// `c4d54f87`). The port names the rule rather than the locale string, so the wording an answer
/// writes from it is its own; the reference's message names are in `docs/reference-notes.md`.
public enum CategoryValidationRule: String, CaseIterable, Sendable {
    /// `error.title_required`: the title the request carries is empty.
    case titleRequired

    /// `error.category_already_exists`: another category of the same user has this title, read
    /// through the lowercased form.
    case alreadyExists
}
