// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/atom/atom_common.go (`atomLinks`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// One `atom:link` element as the reference reads it. The attributes are the values `copyValue`
/// assigns, with no trim, so every trim in the rules below is the rule the reference applies at
/// this point.
struct AtomLink: Equatable, Sendable {
    var element: XMLElement

    var href: String { attribute(local: "href") }
    var type: String { attribute(local: "type") }
    var rel: String { attribute(local: "rel") }
    var length: String { attribute(local: "length") }

    /// The link elements at the element's own level, in the namespace the field tag names.
    static func read(from scope: XMLElement, namespace: String) -> [AtomLink] {
        scope.children(local: "link", namespace: namespace).map { AtomLink(element: $0) }
    }

    /// `originalLink()`: the relation `alternate`, or no relation with no type or with the HTML
    /// type. The first link that answers wins, and the two checks are made on the same link, so a
    /// link with no relation is answered by its type rather than by the next link.
    static func originalLink(_ links: [AtomLink]) -> String {
        for link in links {
            if equalFold(link.rel, "alternate") { return UnicodeSpace.trim(link.href) }
            if link.rel.isEmpty, link.type.isEmpty || link.type == "text/html" {
                return UnicodeSpace.trim(link.href)
            }
        }
        return ""
    }

    /// `firstLinkWithRelation(_:)`.
    static func firstLinkWithRelation(_ links: [AtomLink], relation: String) -> String {
        for link in links where equalFold(link.rel, relation) { return UnicodeSpace.trim(link.href) }
        return ""
    }

    /// `firstLinkWithRelationAndType(_:)`: the type is checked inside the relation, so the order of
    /// the list is what decides between two links that carry the same relation.
    static func firstLinkWithRelationAndType(_ links: [AtomLink], relation: String, contentTypes: [String])
        -> String {
        for link in links where equalFold(link.rel, relation) {
            for contentType in contentTypes where equalFold(link.type, contentType) {
                return UnicodeSpace.trim(link.href)
            }
        }
        return ""
    }

    /// `findAllLinksWithRelation(_:)` — an href that is empty after the trim is not a link at all,
    /// which is what the two rules above do not check. The href here is the trimmed one, as the
    /// reference assigns it.
    static func linksWithRelation(_ links: [AtomLink], relation: String) -> [AtomLink] {
        links.filter { equalFold($0.rel, relation) && !UnicodeSpace.trim($0.href).isEmpty }
    }

    /// The fold `strings.EqualFold` does on its ASCII fast path. The reference folds the rest
    /// through `unicode.SimpleFold`, so a relation written with a letter that folds to an ASCII
    /// letter matches there and not here — recorded in `docs/parity.md`. The Text construct's
    /// `xhtml` type gate is compared with this fold, which is what the reference's
    /// `strings.EqualFold(t.Type, "xhtml")` does.
    static func equalFold(_ left: String, _ right: String) -> Bool {
        func fold(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }
        return [UInt8](left.utf8).map(fold) == [UInt8](right.utf8).map(fold)
    }

    private func attribute(local: String) -> String {
        element.attribute(local: local) ?? ""
    }
}
