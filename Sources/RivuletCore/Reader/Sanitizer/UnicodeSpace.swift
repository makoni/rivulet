// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from the rules Go's `unicode.IsSpace` and `strings` package apply in
// Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The whitespace rules the text layer reads through: the set `unicode.IsSpace` has, the split
/// `FieldsSeq` does, and the trim `strings.TrimSpace` does.
///
/// What `IsSpace` answers with is the `White_Space` table Go generates from the UCD property, which
/// is what a Swift scalar reports. Its comment also names category Z and `Pattern_White_Space`, but
/// the table has neither the four separators `U+001C` to `U+001F` nor `U+200E` and `U+200F`, so the
/// port does not add them. The three places that need the set — the split, the trim and the space
/// check in `TruncateHTML` — read the same rule.
enum UnicodeSpace {
    /// The table `IsSpace` reads, as `unicode/graphic.go` and `unicode/tables.go` build it: the
    /// Latin-1 fast path answers true for only the eight characters the comment names, and the
    /// table used above Latin-1 is the UCD property. That is the same set Swift's scalar property
    /// has, which the tests pin on the code points a reading of the comment alone would get wrong.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// `FieldsSeq`: runs of whitespace split the value into words, and an empty piece is not a
    /// word.
    static func fields(_ value: String) -> [[Unicode.Scalar]] {
        var words: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for scalar in value.unicodeScalars {
            if isSpace(scalar) {
                if !current.isEmpty {
                    words.append(current)
                    current = []
                }
                continue
            }
            current.append(scalar)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// `TrimSpace`, from both ends, on the same set.
    static func trim(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && isSpace(scalars[start]) { start += 1 }
        while end > start && isSpace(scalars[end - 1]) { end -= 1 }

        var out = String()
        for scalar in scalars[start..<end] { out.unicodeScalars.append(scalar) }
        return out
    }
}
