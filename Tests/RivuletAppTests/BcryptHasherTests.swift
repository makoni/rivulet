import Testing
import RivuletApp

/// Password hashes through Vapor's `BCryptDigest`, which is the port's own type because a bcrypt
/// implementation is already in the dependency graph and no new dependency is approved. The cost is
/// the reference's: `bcrypt.DefaultCost` is 10 at the version `go.mod` pins
/// (`golang.org/x/crypto v0.54.0`), while Vapor's `hash` defaults to 12, so the cost is passed
/// explicitly here, and that is the rule the first pin reads.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the cost written
/// is the reference's 10, which a patch that calls `hash` without a cost fails; the stored value is
/// the hash and not the plaintext, which a patch returning the plaintext fails; verification
/// accepts the password it was created from and rejects another, which a patch that answers as a
/// match without comparing fails; the salt is random, which a patch that hashes one password to one
/// value fails, because two hashes then compare equal while the pins still call them different; the
/// plaintext longer than the reference's 72-byte limit is refused on both paths, which a patch that
/// drops the guard fails — Vapor's C implementation truncates the plaintext at 72 bytes (
/// `CVaporBcrypt/bcrypt.c`), so without the guard a 73-byte plaintext whose first 72 bytes are the
/// stored password answers as a match, where the reference's package reports the length as an
/// error; and a hash written at the reference's marker verifies here, which a patch that admits
/// only this port's marker fails.
///
/// What they cannot fail on: the revision marker this port writes, which is `$2b$` where the
/// reference writes `$2a$` — recorded in `docs/parity.md`, and the pin that reads a reference hash
/// shows the two stay interchangeable rather than pinning which marker the port writes; the
/// boundary between the salt and the checksum, which bcrypt writes as one run with no separator, so
/// the pin reads the digest block as a whole; the work factor's timing, which no pin reads; and the
/// wording of the refused-length error, which is the port's own.
@Suite struct BcryptHasherTests {
    private let hasher = BcryptHasher()

    @Test func theCostWrittenIsTheReferenceCost() throws {
        let fields = fields(of: try hasher.hash("secret"))
        #expect(fields.count == 4, "the shape is marker, cost, digest block: \(fields)")
        #expect(fields[2] == "10", "the cost field is the reference's default: \(fields)")
        #expect(fields[3].count == 53, "the digest block, which bcrypt writes as one run: \(fields)")
    }

    @Test func theStoredValueIsTheHashNotThePlaintext() throws {
        let hash = try hasher.hash("secret")
        #expect(hash != "secret")
        #expect(!hash.contains("secret"), "the password does not appear in the stored value: \(hash)")
    }

    @Test func verificationAcceptsThePasswordItWasCreatedFromAndRejectsAnother() throws {
        let hash = try hasher.hash("secret")
        #expect(try hasher.verify("secret", hash: hash))
        #expect(!(try hasher.verify("longpass", hash: hash)))
        // Both sides of this pair are inside the reference's limit, so a patch that only kept the
        // length guard would still have to compare the digests to fail the second line.
        #expect(!(try hasher.verify("short", hash: hash)))
    }

    @Test func twoHashesOfOnePasswordDifferAndBothVerify() throws {
        let first = try hasher.hash("secret")
        let second = try hasher.hash("secret")
        #expect(first != second, "the salt is random: \(first) vs \(second)")
        #expect(try hasher.verify("secret", hash: first))
        #expect(try hasher.verify("secret", hash: second))
    }

    @Test func aHashWrittenAtTheReferenceMarkerVerifiesHere() throws {
        // Written by the reference at the pinned cost: `bcrypt.GenerateFromPassword("secret", 10)`,
        // which is what a Miniflux account row holds. The marker is not asserted here — it is the
        // difference recorded in `docs/parity.md`; what is pinned is that the two stay compatible.
        let referenceHash = "$2a$10$BY.PtuLLSYpEHB/4r0SaWutP2Lqwg58suDiGf6IkCAU4CH9W9v2s."
        #expect(try hasher.verify("secret", hash: referenceHash))
    }

    @Test func aPlaintextLongerThanTheReferenceLimitIsRefusedOnBothPaths() throws {
        let long = String(repeating: "a", count: 73)
        #expect(throws: BcryptHasher.HashError.passwordTooLong) {
            try hasher.hash(long)
        }
        // The same plaintext against a hash of its first 72 bytes: without the guard this answers
        // as a match, because Vapor's C path truncates, where the reference reports the length as
        // an error.
        let stored = try hasher.hash(String(repeating: "a", count: 72))
        #expect(throws: BcryptHasher.HashError.passwordTooLong) {
            try hasher.verify(long, hash: stored)
        }

        // The boundary the reference accepts: exactly 72 bytes hashes and verifies.
        let boundary = String(repeating: "a", count: 72)
        let boundaryHash = try hasher.hash(boundary)
        #expect(try hasher.verify(boundary, hash: boundaryHash))
    }

    /// The hash read as its fields: an empty part, the marker, the cost, the digest block.
    private func fields(of hash: String) -> [String] {
        hash.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
    }
}
