// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/crypto/crypto.go (`SHA256`) (Apache-2.0); adapted for Swift/SQLite,
// through the pre-approved `swift-crypto`.

import Crypto
import Foundation

/// The checksum the reader writes for the values it identifies by hash: an entry identity and an icon
/// the storage layer deduplicates by hash.
enum Hashes {
    /// `SHA256`: the checksum of the value as its UTF-8 bytes, written as lower-case hexadecimal.
    static func sha256(_ value: String) -> String {
        digest(SHA256.hash(data: Data(value.utf8)))
    }

    /// `hex.EncodeToString`, which writes two digits per byte, so the hex is exactly one block wide.
    private static func digest(_ hash: SHA256Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }
}
