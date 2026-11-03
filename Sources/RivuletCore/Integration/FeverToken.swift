// Ported from Miniflux internal/ui/integration_update.go's token derivation (Apache-2.0); adapted
// for Swift/SQLite, through the pre-approved `swift-crypto`.

import Crypto
import Foundation

/// The Fever `api_key` value the reference stores for a user.
///
/// Upstream derives it in `internal/ui/integration_update.go`:
/// `fmt.Sprintf("%x", md5.Sum([]byte(fever_username + ":" + fever_password)))`. The two parts are
/// joined with a colon and hashed as their UTF-8 bytes, and the digest is written as lowercase hex,
/// the same shape `Hashes.sha256` writes for entry identity. The parts are used as read — only the
/// printed digest is lowercased — so the same pair written in another case is a different value,
/// which `FeverTokenTests` pins against the reference's output at the toolchain `go.mod` pins. The
/// lowercasing happens only on the lookup the Fever router does with the stored value,
/// `lower(integrations.fever_token)=lower($1)`, which arrives with that router.
public enum FeverToken {
    /// `md5(username + ":" + password)`, written as lowercase hex.
    public static func derive(username: String, password: String) -> String {
        digest(Insecure.MD5.hash(data: Data((username + ":" + password).utf8)))
    }

    /// `hex.EncodeToString`, which writes two digits per byte, so the hex is exactly one block
    /// wide.
    private static func digest(_ hash: Insecure.MD5.Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }
}
