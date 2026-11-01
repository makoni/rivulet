// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/crypto/crypto.go (`SHA256`) (Apache-2.0); adapted for Swift/SQLite,
// through the pre-approved `swift-crypto`.

import Crypto
import Foundation

/// The checksum the reader writes for the values it identifies by hash. The reference hashes an
/// entry with `SHA256` and an icon with `HashFromBytes`, which is FNV-128a; this port has
/// SHA-256 for both, so an icon's stored hash value differs from the reference's — recorded in
/// `docs/parity.md`.
enum Hashes {
    /// `SHA256`: the checksum of the value as its UTF-8 bytes, written as lower-case hexadecimal.
    static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    /// The same checksum over raw bytes, which is the slot the reference's `HashFromBytes` fills.
    static func sha256(_ data: Data) -> String {
        digest(SHA256.hash(data: data))
    }

    /// `hex.EncodeToString`, which writes two digits per byte, so the hex is exactly one
    /// block wide.
    private static func digest(_ hash: SHA256Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }
}
