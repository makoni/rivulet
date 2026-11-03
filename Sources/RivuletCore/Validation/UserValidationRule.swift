// Ported from Miniflux internal/validator/user.go (Apache-2.0); adapted for Swift/SQLite.

/// The rule a user name or a password fails on.
///
/// The cases are the reference's four localized errors (`internal/validator/user.go` at commit
/// `c4d54f87`). The port names the rule rather than the locale string, so the wording a command
/// prints from it is its own; the reference's message names are in `docs/reference-notes.md`.
public enum UserValidationRule: String, CaseIterable, Sendable {
    /// `error.user_mandatory_fields`: the name is required.
    case mandatoryFields

    /// `error.user_already_exists`.
    case alreadyExists

    /// `error.invalid_username`: a character outside the class the reference admits.
    case invalidUsername

    /// `error.password_min_length`: the length is counted in bytes, which is what Go's `len()`
    /// counts.
    case passwordMinLength
}
