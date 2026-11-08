// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/subscription/finder.go (`findSubscriptionsFromWebPage`)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The type test is the reference's dispatch, so the value is compared as the attribute holds it:
/// there is no fold here, which is what `SubscriptionDocumentLinksTests` pins on the case that says
/// so. The relation test is this port's own — the reference reads the type attribute alone — and
/// the whole value is compared, folded, which is what the same suite pins. Both are the rules the
/// scan reads; the scan's own order, the dedupe and the resolution are in that file.
enum SubscriptionLinkRules {
    /// The WordPress test is part of the `application/json` case, not of the scan: the reference
    /// skips a value whose href names that path inside that branch, so the same path read through
    /// one of the other branches is read. The pin that shows this puts the path in two branches at
    /// once, which is the only input where the two answers can part.
    static func format(forType type: String, href: String) -> FeedFormat? {
        switch type {
        case "application/rss+xml": return .rss
        case "application/atom+xml": return .atom
        case "application/feed+json": return .json
        case "application/json":
            if href.contains("/wp-json/") { return nil }
            return .json
        default: return nil
        }
    }

    /// The relation test this port adds for the scan the plan names. The value is the whole
    /// attribute, read through the same fold the parser's relation rule uses.
    static func isAlternateLink(rel: String) -> Bool {
        AtomLink.equalFold(rel, "alternate")
    }
}
