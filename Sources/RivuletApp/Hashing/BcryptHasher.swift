// Ported from Miniflux internal/crypto/crypto.go's bcrypt use (Apache-2.0); adapted for Swift,
// through Vapor's `BCryptDigest`, which is already in the dependency graph: no new dependency is
// approved for hashing.

import Vapor

/// Creates and checks password hashes.
///
/// The cost is the reference's: `bcrypt.DefaultCost` is 10 at the version `go.mod` pins
/// (`golang.org/x/crypto v0.54.0`), while Vapor's `hash` defaults to 12, so the cost is passed
/// explicitly. The reference writes hashes with the `$2a$` marker and this port writes `$2b$`, the
/// same algorithm under a different marker, recorded in `docs/parity.md`; a hash written at the
/// reference's marker verifies through this type, which is what `BcryptHasherTests` pins.
///
/// The 72-byte limit is the reference's, and it belongs to the hash path only: Go's package reports
/// a plaintext longer than 72 bytes as an error when it creates a hash, while its comparison reads
/// at most the first 72 key bytes, so a longer plaintext that shares those bytes answers as a
/// match. Vapor's C implementation truncates the plaintext the same way, so `verify` needs no
/// guard: it answers as the reference does. This is a one-shot path — one hash per command run, or
/// one comparison per authenticated request — so it runs on the caller's task rather than as a
/// loop.
public struct BcryptHasher: Sendable {
    /// `bcrypt.DefaultCost`, the cost the reference writes.
    public static let referenceCost = 10

    /// The longest plaintext the reference's package accepts when it creates a hash, in bytes.
    public static let maximumPasswordBytes = 72

    /// The plaintext the reference's package reports as too long, on the hash path.
    public enum HashError: Error, Equatable, Sendable {
        case passwordTooLong
    }

    /// Creates the hasher. It holds no state, so it is `Sendable`: a command captures it across the
    /// storage checkout.
    public init() {}

    /// Creates a hash for `password` at the reference cost.
    ///
    /// - Throws: `HashError.passwordTooLong` for a plaintext past the reference's limit, and the
    ///   digest's own errors for a cost or a salt it rejects.
    public func hash(_ password: String) throws -> String {
        guard password.utf8.count <= Self.maximumPasswordBytes else {
            throw HashError.passwordTooLong
        }
        return try Bcrypt.hash(password, cost: Self.referenceCost)
    }

    /// Checks `password` against a stored hash. No length check here, as the reference has none:
    /// the comparison reads at most the first 72 key bytes, so a plaintext past the hash-path limit
    /// answers as a match when its first 72 bytes are the stored password.
    ///
    /// - Returns: `true` when the stored hash was created from `password`, or from its first 72
    ///   bytes.
    public func verify(_ password: String, hash stored: String) throws -> Bool {
        try Bcrypt.verify(password, created: stored)
    }
}
