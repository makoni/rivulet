// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/rss/adapter.go (`findEntryEnclosures`) (Apache-2.0); adapted
// for Swift/SQLite. The media element rules and the collection are `MediaRules`; what is RSS's own
// here is the order the groups are walked in and the enclosure element itself.

import Foundation

/// The attachments an RSS entry has, in the order `findEntryEnclosures` walks them: the media
/// thumbnails, the RSS enclosures, the media contents, then the media peer links. Each group reads
/// the item's own elements first and then the group's, and the whole list is deduplicated by the
/// resolved URL.
enum RSSMedia {
    /// One attachment list for one item, resolved against the site URL the reference resolves them
    /// against.
    static func enclosures(item: XMLElement, siteURL: String) -> [ParsedEnclosure] {
        let groups = MediaRules.elements(item, local: "group")
        var candidates: [MediaRules.Candidate] = []

        for thumbnail in MediaRules.grouped(item, groups, local: "thumbnail") {
            // RSS resolves first and compares the resolved value, which is the Atom rule's other
            // half.
            candidates.append(MediaRules.thumbnail(thumbnail, comparedBeforeResolution: false))
        }

        for enclosure in rssFields(item, local: "enclosure") {
            // The FeedBurner check reads the URL as it was written, before the reference trims it,
            // and an enclosure keeps a URL that cannot be resolved rather than dropping it.
            var url = attribute(enclosure, local: "url")
            let original = fieldValue(item, local: "origEnclosureLink", namespace: FeedNamespaces.feedBurner)
            if !original.isEmpty, url.hasSuffix(pathBase(original)) { url = original }

            candidates.append(MediaRules.Candidate(url: url, mimeType: attribute(enclosure, local: "type"),
                size: enclosureSize(attribute(enclosure, local: "length")), dropsWhenUnresolvable: false))
        }

        for content in MediaRules.grouped(item, groups, local: "content") {
            candidates.append(MediaRules.content(content))
        }

        for peerLink in MediaRules.grouped(item, groups, local: "peerLink") {
            candidates.append(MediaRules.peerLink(peerLink))
        }

        return MediaRules.enclosures(siteURL: siteURL, candidates: candidates)
    }

    // MARK: - What the RSS enclosure element carries

    /// `strconv.ParseInt`, which answers zero for a value it cannot read. The enclosure checks the
    /// empty value before the parse, which is the only place the media rule and this one differ.
    private static func enclosureSize(_ length: String) -> Int {
        UnicodeSpace.trim(length).isEmpty ? 0 : Int(length) ?? 0
    }

    // MARK: - Reading the tree

    /// A direct child the reference's field tag `rss <local>` reads: the default space stands in
    /// for a name that had no prefix, which is what `translate` does for an element name.
    private static func rssFields(_ element: XMLElement, local: String) -> [XMLElement] {
        element.children(local: local, namespace: FeedNamespaces.rssDefault,
            defaultSpace: FeedNamespaces.rssDefault)
    }

    private static func fieldValue(_ element: XMLElement, local: String, namespace: String) -> String {
        element.child(local: local, namespace: namespace, defaultSpace: FeedNamespaces.rssDefault)?.text ?? ""
    }

    private static func attribute(_ element: XMLElement, local: String) -> String {
        element.attribute(local: local) ?? ""
    }

    /// Go's `path.Base`: the last segment, with the trailing separators dropped, `.` when nothing
    /// is written at all, and `/` when what is left is only separators.
    private static func pathBase(_ path: String) -> String {
        var value = path
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        guard !value.isEmpty else { return path.isEmpty ? "." : "/" }
        if let lastSlash = value.lastIndex(of: "/") { return String(value[value.index(after: lastSlash)...]) }
        return value
    }
}
