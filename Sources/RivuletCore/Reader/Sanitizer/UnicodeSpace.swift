// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from the rules Go's `unicode.IsSpace` and `strings` package apply in
// Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The whitespace rules the text layer reads through: the set `unicode.IsSpace` has, the split
/// `FieldsSeq` does, and the trim `strings.TrimSpace` does.
///
/// Go's set is the Unicode `White_Space` property plus category Z plus `Pattern_White_Space`, which
/// is what a Swift scalar reports except for the four separators the last set adds, named below.
/// The three places that need the set — the split, the trim and the space check in `TruncateHTML` —
/// read the same rule, and `U+0085` and `U+00A0` are in it.
enum UnicodeSpace {
    /// The contract `unicode.IsSpace` documents: `White_Space`, category Z and
    /// `Pattern_White_Space`. There is no Go toolchain on this machine, so this reads the
    /// documented contract rather than the generated table, and the four characters are named so
    /// the port answers the rule Go documents.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        if (0x001C...0x001F).contains(scalar.value) { return true }
        return scalar.properties.isWhitespace
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
