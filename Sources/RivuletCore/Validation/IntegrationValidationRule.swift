// Ported from Miniflux internal/ui/integration_update.go's duplicate checks (Apache-2.0); adapted
// for Swift/SQLite.

/// The rule an integration name fails on.
///
/// The cases are the reference's two localized errors (`error.duplicate_fever_username` and
/// `error.duplicate_googlereader_username`), which the port names as rules; the wording a command
/// prints from them is its own, and the reference's names are recorded in
/// `docs/reference-notes.md`.
public enum IntegrationValidationRule: String, CaseIterable, Sendable {
    /// `error.duplicate_fever_username`: another row holds this Fever name.
    case duplicateFeverUsername

    /// `error.duplicate_googlereader_username`: another row holds this Google Reader name.
    case duplicateGoogleReaderUsername
}
