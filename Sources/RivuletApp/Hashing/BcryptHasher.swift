// Ported from Miniflux internal/crypto/crypto.go's bcrypt use (Apache-2.0); adapted for Swift,
// through Vapor's `BCryptDigest`, which is already in the dependency graph: no new dependency is
// approved for hashing.

import Vapor

/// Creates and checks password hashes.
///
/// The cost is the reference's: `bcrypt.DefaultCost` is 10 at the version `go.mod` pins
/// (`golang.org/x/crypto v0.54.0`), while Vapor's `hash` defaults to 12, so the cost is passed
/// explicitly. The reference writes hashes with the `$2a$` marker and this port writes `$2b$`, the
/// same algorithm under a different marker, recorded in `docs/parity.md`; a hash written at either
/// marker verifies through this type, which is what `BcryptHasherTests` pins.
///
/// The plaintext limit is the reference's too: Go's package reports a plaintext longer than 72
/// bytes as an error on both paths, while Vapor's C implementation truncates the plaintext
/// silently, so without the guard here a 73-byte plaintext whose first 72 bytes are the stored
/// password would answer as a match. The guard keeps the port on the reference's side. This is a
/// one-shot path — one hash per command run, or one comparison per authenticated request — so it
/// runs on the caller's task rather than as a loop.
public struct BcryptHasher: Sendable {
    /// `bcrypt.DefaultCost`, the cost the reference writes.
    public static let referenceCost = 10

    /// The longest plaintext the reference's package accepts, in bytes.
    public static let maximumPasswordBytes = 72

    /// The plaintext the reference's package reports as too long.
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
        try check(password)
        return try Bcrypt.hash(password, cost: Self.referenceCost)
    }

    /// Checks `password` against a stored hash.
    ///
    /// - Throws: `HashError.passwordTooLong` for a plaintext past the reference's limit — the
    ///   reference reports the length as an error here rather than answering whether a truncated
    ///   plaintext matches.
    /// - Returns: `true` when the stored hash was created from `password`.
    public func verify(_ password: String, hash stored: String) throws -> Bool {
        try check(password)
        return try Bcrypt.verify(password, created: stored)
    }

    private func check(_ password: String) throws {
        guard password.utf8.count <= Self.maximumPasswordBytes else {
            throw HashError.passwordTooLong
        }
    }
}
