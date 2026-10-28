// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`truncate.go`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The shortened text the format adapters write: the tags are dropped through the same walk
/// `StripTags` uses, every run of whitespace becomes one space, and the result is cut at the limit.
///
/// The limit counts code points, which is what the reference counts, so a character made of more
/// than one code point is more than one against the limit. That is why the walk here is over the
/// scalars rather than over Swift's `Character` grapheme clusters.
enum TruncateHTML {
    static func truncate(_ input: String, limit: Int) -> String {
        var walk = Walk()
        StripTags.iterate(input) { token in step(&walk, token: token, limit: limit) }
        if walk.count > limit { walk.output.unicodeScalars.append("\u{2026}") }
        return walk.output
    }

    /// One text token, the loop `TruncateHTML` runs for each of them. What the step answers with is
    /// what the yield answers with, and false is what stops the walk at the limit.
    private static func step(_ walk: inout Walk, token: String, limit: Int) -> Bool {
        // A space before a tag is kept, but only when something has already been written, and the
        // first code point of the token is what decides it.
        if walk.words > 0, let first = token.unicodeScalars.first {
            walk.needspace = walk.needspace || UnicodeSpace.isSpace(first)
        }

        for word in UnicodeSpace.fields(token) {
            // The space counts toward the limit before it is written, which is what cuts a word
            // that would otherwise fit.
            if walk.needspace {
                walk.count += 1
                if walk.count > limit { return false }
            }

            let wordlen = countWord(word, walk: &walk, limit: limit)

            // This is the only place a space is written, which is why a run of spaces becomes one
            // space. `wordlen > 0` is what skips it when nothing printable is left in the word.
            if walk.needspace && wordlen > 0 { walk.output += " " }
            for scalar in word[0..<wordlen] { walk.output.unicodeScalars.append(scalar) }

            if walk.count > limit { return false }

            walk.needspace = true
            walk.words += 1
        }

        // The space after a tag is the last code point of the token, and only when something has
        // already been written.
        walk.needspace = walk.words > 0 && (token.unicodeScalars.last.map(UnicodeSpace.isSpace) ?? false)
        return true
    }

    /// How much of the word the limit leaves, counted in code points. Go stops at the code point
    /// that passes the limit, so a partial character is never written.
    private static func countWord(_ word: [Unicode.Scalar], walk: inout Walk, limit: Int) -> Int {
        var wordlen = 0
        while wordlen < word.count {
            walk.count += 1
            if walk.count > limit { break }
            wordlen += 1
        }
        return wordlen
    }

    private struct Walk {
        var output = ""
        var words = 0
        var count = 0
        var needspace = false
    }
}
