// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`strip_tags.go`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The text layer the format adapters read through: the tags are dropped and what is written is the
/// text tokens the tokenizer reads.
///
/// The reference uses this for cosmetic output only, not to make content safe — dropping the tags
/// is not what removes the active content, and the sanitizer is the layer that does that.
enum StripTags {
    /// The input without the tags, trimmed the way `strings.TrimSpace` trims it.
    static func strip(_ input: String) -> String {
        var output = ""
        iterate(input) { text in
            output += text
            return true
        }
        return UnicodeSpace.trim(output)
    }

    /// `stripIter`, the walk both the text-layer functions run through: the yield is called for
    /// each text token and every other kind is skipped, and a yield that answers false stops the
    /// walk, which is what `TruncateHTML` uses to stop at the limit.
    ///
    /// The reference reports a reader error and writes nothing when it happens. There is no reader
    /// here, because the input is already a string, so that path has no equivalent and is recorded
    /// in `docs/parity.md`.
    @discardableResult
    static func iterate(_ input: String, yield: (String) -> Bool) -> Bool {
        let tokenizer = HTMLTokenizer(input)
        while let token = tokenizer.next() {
            guard token.kind == .text else { continue }
            if !yield(token.data) { return false }
        }
        return true
    }
}
