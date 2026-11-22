// Ported from Miniflux internal/api/middleware.go's validateAPIKeyAuth and validateBasicAuth
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore

/// The read every request of this path runs through before it reaches a route.
///
/// The two halves run in the reference's order, which `RestV1AuthTests` pins: the key half first,
/// and the basic half only when the key half read nothing. Upstream's `IsAuthenticated` guard is
/// the answer the first half already gives, so it is not repeated here. The `WWW-Authenticate`
/// name the reference's basic half writes before its guards is written here by the response half,
/// and both that name's rule and the status each answer gets are pinned as pure logic by
/// `RestV1ResponseTests`.
struct RestV1Auth: Sendable {
    private let storage: SQLiteStorage
    private let hasher: BcryptHasher

    init(storage: SQLiteStorage, hasher: BcryptHasher) {
        self.storage = storage
        self.hasher = hasher
    }

    /// `validateAPIKeyAuth`: an empty value is not read against the storage layer at all, which is
    /// the rule the pin reads; a value is read against the key table by the token and compared as
    /// read, and the row the join reaches is the account the key belongs to. For "no row" the
    /// answer is the failure rule.
    ///
    /// What this half does not have: `SetLastLogin` and `SetAPIKeyUsedTimestamp`, which the
    /// reference writes after the read passes — no column for the first, and no piece that writes
    /// the second — so neither has anything to pin here.
    func authenticate(headers: RestV1Headers) async throws -> RestV1AuthOutcome {
        let token = headers.value(named: "X-Auth-Token")
        if token.isEmpty { return try await basicHalf(headers) }

        let user: User?
        do {
            user = try await storage.withConnection { connection in
                try await ApiKeyRepository(connection).userByAPIKey(token)
            }
        } catch {
            // Upstream answers the JSON 500 shape for a read that fails, which no input this suite
            // can build reaches, so the branch is stated rather than pinned.
            return .storageFailure(rule: .apiKeyReadFailed)
        }
        guard let user, let userID = user.id else { return .unauthorized(rule: .noApiKeyRow) }
        return .authenticated(userID: userID)
    }

    /// `validateBasicAuth`: the guard that an empty name or an empty password ends the read before
    /// the storage layer is read, the compare with the stored bcrypt hash, and the row read for the
    /// name. The name is read as the account lookup reads it, lowercase, which
    /// `UserRepositoryTests` pins and the auth pin reads again here.
    private func basicHalf(_ headers: RestV1Headers) async throws -> RestV1AuthOutcome {
        let credentials = headers.basicCredentials()
        guard credentials.read else { return .unauthorized(rule: .noAuthorizationValue) }
        guard !credentials.name.isEmpty, !credentials.password.isEmpty else {
            return .unauthorized(rule: .emptyNameOrPassword)
        }

        // Upstream reads the stored hash, compares, and then reads the row. One read serves both
        // here, so the order between the compare and the read has nothing to pin, and the two
        // failure branches share one status upstream: what the pins read is which branch fired, and
        // the names are the port's own. The dummy comparison upstream runs for a name with no row,
        // to keep the timing the same, has no piece here.
        let user: User?
        do {
            user = try await storage.withConnection { connection in
                try await UserRepository(connection).fetch(username: credentials.name)
            }
        } catch {
            return .storageFailure(rule: .userReadFailed)
        }
        guard let user, let userID = user.id else { return .unauthorized(rule: .noUserRow) }

        do {
            if try hasher.verify(credentials.password, hash: user.passwordHash) {
                return .authenticated(userID: userID)
            }
        } catch {
            // A stored value that is not a hash is the error upstream's compare reports, which is
            // the same answer as a mismatch.
        }
        return .unauthorized(rule: .passwordMismatch)
    }
}
