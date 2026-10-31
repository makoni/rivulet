// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`findIconURLsFromHTMLDocument`, the
// selector) (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The rule the icon selector reads a `link` element's `rel` with.
///
/// The reference's query is the four branches `link[rel='icon' i][href]`,
/// `link[rel='shortcut icon' i]`, `link[rel='icon shortcut' i]` and
/// `link[rel='apple-touch-icon'][href]`. Only the three `icon` branches carry the `i` flag, so
/// `apple-touch-icon` is compared as it was written, and every branch compares the whole value,
/// so a `rel` with a space at the end is not the branch. The attribute name is lower-cased by
/// the tokenizer, which is the value `TagAttr` gives the selector.
enum IconLinkRules {
    /// Whether `rel` is one of the four branches.
    static func isIconLink(rel: String) -> Bool {
        if rel == "apple-touch-icon" { return true }

        switch rel.lowercased() {
        case "icon", "shortcut icon", "icon shortcut":
            return true
        default:
            return false
        }
    }
}
