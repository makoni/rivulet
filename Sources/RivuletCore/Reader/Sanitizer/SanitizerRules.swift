// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The predicates the sanitizer answers with before it writes an element, the small rules the
/// reference splits out of `filterAndRenderHTML`.
enum SanitizerRules {
    /// The tags whose content is dropped with the tag, which are the three that can carry script.
    static func isBlockedTag(_ tag: String) -> Bool {
        ["noscript", "script", "style"].contains(tag)
    }

    /// The attributes that hold a URL, which are the ones resolved and checked against the scheme
    /// allowlist.
    static func isExternalResourceAttribute(_ name: String) -> Bool {
        ["src", "href", "poster", "cite"].contains(name)
    }

    /// The tags written without a closing part, which is the reference's list, not the HTML5 void
    /// set: `area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`, `meta`, `param`,
    /// `source`, `track`, `wbr`.
    static func isSelfContainedTag(_ tag: String) -> Bool {
        ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
            "track", "wbr"].contains(tag)
    }

    static func isHidden(_ node: HTMLNode) -> Bool {
        node.attributes.contains { $0.name == "hidden" }
    }

    /// A one-pixel image is a tracker: both dimensions present, each one the digit `1` or `0`,
    /// checked on the attribute values as they were read.
    static func isPixelTracker(_ tag: String, attributes: [HTMLAttribute]) -> Bool {
        if tag != "img" { return false }

        var hasHeight = false
        var hasWidth = false
        for attribute in attributes {
            guard attribute.value == "1" || attribute.value == "0" else { continue }
            if attribute.name == "height" { hasHeight = true }
            if attribute.name == "width" { hasWidth = true }
        }
        return hasHeight && hasWidth
    }

    /// `isPositiveInteger`: an integer with an optional sign, greater than zero. `10px` and an
    /// empty value are not one.
    static func isPositiveInteger(_ value: String) -> Bool {
        if value.isEmpty { return false }
        guard let number = Int(value) else { return false }
        return number > 0
    }

    static func isValidDecodingValue(_ value: String) -> Bool {
        ["sync", "async", "auto"].contains(value)
    }

    static func isValidFetchPriorityValue(_ value: String) -> Bool {
        ["high", "low", "auto"].contains(value)
    }
}
