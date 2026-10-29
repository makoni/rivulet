// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser (the normalized model the adapters fill); adapted for
// Swift/SQLite.

/// An attachment an adapter found on an entry.
///
/// `size` is what the format declares: a value that is not a number is zero, and the adapters do not
/// measure the file. `url` is the resolved URL, which is also what the deduplication compares.
struct ParsedEnclosure: Equatable, Sendable {
    var url: String
    var mimeType: String
    var size: Int
}
