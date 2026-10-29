// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser (the normalized model the adapters fill); adapted for
// Swift/SQLite.

/// An entry as one of the format adapters fills it, before sanitization and before the storage layer.
///
/// `hash` is the identity the reference stores, `date` is the parsed date with the zone the parse
/// resolved to, and `content` is the content as the format wrote it — sanitization is the next layer,
/// so nothing here is made safe yet.
struct ParsedEntry: Equatable, Sendable {
    var hash: String
    var title: String
    var url: String
    var commentsURL: String
    var author: String
    var content: String
    var language: String
    var date: ParsedDate
    var tags: [String]
    var enclosures: [ParsedEnclosure]

    /// The reading time, in minutes: what a podcast declares as its duration. Go's `ReadingTime` is
    /// an integer there, so the minutes are kept as an integer.
    var readingTimeMinutes: Int
}
