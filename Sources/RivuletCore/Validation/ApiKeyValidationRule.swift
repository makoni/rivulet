// Ported from Miniflux internal/validator/api_key.go (Apache-2.0); adapted for Swift/SQLite.

/// The rule an api-key description fails on.
///
/// The cases are the reference's two localized errors, `error.fields_mandatory` and
/// `error.api_key_already_exists` (`internal/validator/api_key.go` at commit `c4d54f87`). The port
/// names the rule rather than the locale string, so the wording a command prints from it is its
/// own; the names are recorded in `docs/reference-notes.md`.
public enum ApiKeyValidationRule: String, CaseIterable, Sendable {
    /// `error.fields_mandatory`: the description is required.
    case mandatoryFields

    /// `error.api_key_already_exists`: the account already has a key with this description.
    case alreadyExists
}
