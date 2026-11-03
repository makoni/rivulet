// Ported from Miniflux internal/validator/user.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The rules a user name and a password are checked against.
///
/// The order is the reference's: `validateCreation` applies the four rules in the order
/// `ValidateUserCreationWithPassword` reads them, and `UserValidationTests` pins that order. The
/// existence read is handed in as a value, because the storage layer answers it and a rule that
/// read the database could not be pinned as a rule: `UserRepositoryTests` pins the read, and
/// `CreateAdminTests` pins the command that uses it before any rule is applied.
public enum UserValidation {
    /// The minimum password length, in bytes. Go reads `len(password)`, which counts bytes, so a
    /// three-character password of non-ASCII letters passes here where a character count would not.
    public static let passwordMinimumBytes = 6

    /// Applies the rules in the reference's order and names the first one the input fails on, or
    /// `nil` when it fails none.
    public static func validateCreation(username: String, password: String,
        userExists: Bool) -> UserValidationRule? {
        if username.isEmpty { return .mandatoryFields }
        if userExists { return .alreadyExists }
        if let rule = validateUsername(username) { return rule }
        return validatePassword(password)
    }

    /// `validateUsername`: letters, numbers and the four characters `_`, `-`, `@`, `.`.
    ///
    /// Read per Unicode scalar, as Go reads the string rune by rune, so a combining mark is not a
    /// letter on its own: a letter followed by one is not one allowed character here. That is the
    /// case where a check reading grapheme clusters would admit the name, so the reading is stated
    /// rather than left to the platform default.
    public static func validateUsername(_ username: String) -> UserValidationRule? {
        for scalar in username.unicodeScalars where !isAllowed(scalar) {
            return .invalidUsername
        }
        return nil
    }

    /// `validatePassword`: at least `passwordMinimumBytes` bytes.
    public static func validatePassword(_ password: String) -> UserValidationRule? {
        password.utf8.count < passwordMinimumBytes ? .passwordMinLength : nil
    }

    private static let allowedPunctuation: Set<UnicodeScalar> = ["_", "-", "@", "."]

    private static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
        if allowedPunctuation.contains(scalar) { return true }
        // A single-scalar `Character` is read by its Unicode general category, which is what Go's
        // `unicode.IsLetter` and `unicode.IsNumber` read.
        let character = Character(scalar)
        return character.isLetter || character.isNumber
    }
}
