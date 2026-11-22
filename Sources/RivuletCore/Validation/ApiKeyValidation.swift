// Ported from Miniflux internal/validator/api_key.go (Apache-2.0); adapted for Swift/SQLite.

/// The rules an api-key description is checked against.
///
/// The reference has exactly two, and no character class and no length rule, which is what
/// `ApiKeyValidationTests` pins: a description the user-name class would reject, or one shorter
/// than the password minimum, passes here. The order is the reference's — `ValidateAPIKeyCreation`
/// reads the empty rule before the duplicate answer — and the duplicate answer is handed in as a
/// value, because the storage layer answers it and a rule that read the database could not be
/// pinned as a rule: `ApiKeyRepositoryTests` pins the read, and `CreateApiKeyTests` pins the
/// command that does not read it for an empty description.
public enum ApiKeyValidation {
    /// Applies the rules in the reference's order and names the first one the input fails on, or
    /// `nil` when it fails none.
    public static func validateCreation(description: String, descriptionExists: Bool)
        -> ApiKeyValidationRule? {
        if description.isEmpty { return .mandatoryFields }
        if descriptionExists { return .alreadyExists }
        return nil
    }
}
