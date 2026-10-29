// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser (the normalized model the adapters fill); adapted for
// Swift/SQLite.

/// A feed as one of the format adapters fills it, before sanitization and before the storage layer.
///
/// The reference writes these values through `model.Feed`; the fields the RSS adapter fills are the
/// ones listed here. What the reference does not fill is not modelled: the fetch state the storage
/// layer keeps (the fetch time, the conditional-GET headers, the error counters) is not a parsing
/// result.
struct ParsedFeed: Equatable, Sendable {
    var title: String
    var feedURL: String
    var siteURL: String
    var description: String
    var language: String
    var iconURL: String

    /// The cache lifetime the feed declares, in minutes. Go's `time.Duration` is kept as minutes
    /// because the reference only ever reads it as minutes.
    var ttlMinutes: Int

    var entries: [ParsedEntry]
}
