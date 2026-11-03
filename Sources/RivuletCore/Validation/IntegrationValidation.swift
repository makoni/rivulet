// Ported from Miniflux internal/ui/integration_update.go's duplicate checks (Apache-2.0); adapted
// for Swift/SQLite.

/// The two duplicate-name rules of the integration path.
///
/// The order is the reference's: `internal/ui/integration_update.go` reads the Fever check first
/// and the Google Reader check after it, and `IntegrationValidationTests` pins that order. Each
/// check is guarded by the name not being empty, which is upstream's `!= ""` before the read, and
/// the guard is pinned too. The answers are handed in as values, because the storage layer makes
/// them: a rule that read the database could not be pinned as a rule, so `UserRepositoryTests` pins
/// the reads and `IntegrationCredentialsTests` pins the command that uses them.
public enum IntegrationValidation {
    /// Applies the rules in the reference's order and names the first one the input fails on, or
    /// `nil` when it fails none.
    public static func validate(feverUsername: String, feverNameIsDuplicate: Bool,
        googleReaderUsername: String,
        googleReaderNameIsDuplicate: Bool) -> IntegrationValidationRule? {
        if !feverUsername.isEmpty && feverNameIsDuplicate { return .duplicateFeverUsername }
        if !googleReaderUsername.isEmpty && googleReaderNameIsDuplicate {
            return .duplicateGoogleReaderUsername
        }
        return nil
    }
}
