// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/date/parser.go
// (Apache-2.0); adapted for Swift/SQLite.

/// Date parsing failures, with the reference's two messages.
///
/// A failure of one layout is not reported by the reference; it only reports that no layout
/// matched, so the engine returns no match rather than a per-layout error, and this is the error
/// the entry point produces after the last layout has been tried. Go's own per-layout `ParseError`
/// text is not reproduced.
enum DateParseError: Error, Sendable, Equatable {
    /// The trimmed input is empty, which upstream reports as `date parser: empty value`.
    case empty

    /// No layout matched the input. The reference prints the trimmed input, not the normalized one,
    /// because normalization is what made parsing possible for every other case.
    case failedToParse(input: String)
}

extension DateParseError: CustomStringConvertible {
    var description: String {
        switch self {
        case .empty:
            return "date parser: empty value"
        case .failedToParse(let input):
            return "date parser: failed to parse date \"\(input)\""
        }
    }
}
