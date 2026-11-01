// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (the value `parseImageDataURL` and
// `downloadIcon` build) (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// An icon the search found, before the storage layer decides what to store. The reference
/// writes the model directly, so this port keeps the value here and the repository applies the
/// rules of its own: the normalized content type and the random `external_id`.
///
/// The checksum covers the content bytes, which is the value the storage layer deduplicates by.
/// It is the port's SHA-256, not the reference's `crypto.HashFromBytes` (FNV-128a), which
/// `docs/parity.md` records.
struct IconCandidate: Equatable, Sendable {
    /// Content type as it was read, before the storage layer normalizes it.
    var mimeType: String

    /// The bytes the encoding branch produced, or the bytes the response body was.
    var content: Data

    /// Checksum of `content`, lower-case hexadecimal.
    var hash: String

    init(mimeType: String, content: Data) {
        self.mimeType = mimeType
        self.content = content
        hash = Hashes.sha256(content)
    }
}
