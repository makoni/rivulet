// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/media/media.go and `findEntryEnclosures` in
// internal/reader/rss/adapter.go (Apache-2.0); adapted for Swift/SQLite.

/// The attachments an RSS entry has, in the order `findEntryEnclosures` walks them: the media
/// thumbnails, the RSS enclosures, the media contents, then the media peer links. Each group reads the
/// item's own elements first and then the group's, and the whole list is deduplicated by the resolved
/// URL.
enum RSSMedia {
    /// The attachments for one item, resolved against the site URL the reference resolves them against.
    static func enclosures(item: XMLElement, siteURL: String) -> [ParsedEnclosure] {
        let groups = mediaFields(item, local: "group")
        var found: [ParsedEnclosure] = []
        var seen = Set<String>()

        for thumbnail in grouped(item, groups, local: "thumbnail") {
            add(&found, &seen, siteURL: siteURL, url: attribute(thumbnail, local: "url"), mimeType: "image/*",
                size: 0, skipWhenUnresolvable: true)
        }

        for enclosure in rssFields(item, local: "enclosure") {
            // The FeedBurner check reads the URL as it was written, before the reference trims it.
            var url = attribute(enclosure, local: "url")
            let original = fieldValue(item, local: "origEnclosureLink", namespace: FeedNamespaces.feedBurner)
            if !original.isEmpty, url.hasSuffix(pathBase(original)) { url = original }

            add(&found, &seen, siteURL: siteURL, url: url, mimeType: attribute(enclosure, local: "type"),
                size: enclosureSize(attribute(enclosure, local: "length")), skipWhenUnresolvable: false)
        }

        for content in grouped(item, groups, local: "content") {
            add(&found, &seen, siteURL: siteURL, url: attribute(content, local: "url"),
                mimeType: contentMimeType(content), size: parsedSize(attribute(content, local: "fileSize")),
                skipWhenUnresolvable: true)
        }

        for peerLink in grouped(item, groups, local: "peerLink") {
            add(&found, &seen, siteURL: siteURL, url: attribute(peerLink, local: "href"),
                mimeType: peerLinkMimeType(peerLink), size: 0, skipWhenUnresolvable: true)
        }

        return found
    }

    /// One attachment, added the way the reference adds it: the URL is trimmed, and an empty URL is not
    /// an attachment at all. A media element is skipped when its URL cannot be resolved, while the RSS
    /// enclosure keeps it as it was read.
    private static func add(_ found: inout [ParsedEnclosure], _ seen: inout Set<String>, siteURL: String,
        url: String, mimeType: String, size: Int, skipWhenUnresolvable: Bool
    ) {
        let trimmed = UnicodeSpace.trim(url)
        guard !trimmed.isEmpty else { return }

        var resolved = trimmed
        if let absolute = try? URLResolution.resolveToAbsolute(base: siteURL, relative: trimmed) {
            resolved = absolute
        } else if skipWhenUnresolvable {
            return
        }

        if seen.contains(resolved) { return }
        seen.insert(resolved)
        found.append(ParsedEnclosure(url: resolved, mimeType: mimeType, size: size))
    }

    // MARK: - The rules the three media types carry

    private static func contentMimeType(_ content: XMLElement) -> String {
        let type = attribute(content, local: "type")
        if !type.isEmpty { return type }

        switch attribute(content, local: "medium") {
        case "image": return "image/*"
        case "video": return "video/*"
        case "audio": return "audio/*"
        default: return "application/octet-stream"
        }
    }

    private static func peerLinkMimeType(_ peerLink: XMLElement) -> String {
        let type = attribute(peerLink, local: "type")
        return type.isEmpty ? "application/octet-stream" : type
    }

    /// `strconv.ParseInt`, which answers zero for a value it cannot read. The enclosure checks the empty
    /// value before the parse, which is the only place the two rules differ.
    private static func enclosureSize(_ length: String) -> Int {
        UnicodeSpace.trim(length).isEmpty ? 0 : parsedSize(length)
    }

    private static func parsedSize(_ value: String) -> Int { Int(value) ?? 0 }

    // MARK: - Reading the tree

    /// The item's own elements of this name, then the groups' — the order the merged lists are read in.
    private static func grouped(_ item: XMLElement, _ groups: [XMLElement], local: String) -> [XMLElement] {
        mediaFields(item, local: local) + groups.flatMap { mediaFields($0, local: local) }
    }

    private static func mediaFields(_ element: XMLElement, local: String) -> [XMLElement] {
        element.children(local: local, namespace: FeedNamespaces.media)
    }

    /// A direct child the reference's field tag `rss <local>` reads: the default space stands in for a
    /// name that had no prefix, which is what `translate` does for an element name.
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

    /// Go's `path.Base`: the last segment, with the trailing separators dropped, `.` when nothing is
    /// written at all, and `/` when what is left is only separators.
    private static func pathBase(_ path: String) -> String {
        var value = path
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        guard !value.isEmpty else { return path.isEmpty ? "." : "/" }
        if let lastSlash = value.lastIndex(of: "/") { return String(value[value.index(after: lastSlash)...]) }
        return value
    }
}
