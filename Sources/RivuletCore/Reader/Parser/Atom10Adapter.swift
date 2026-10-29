// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/atom/atom_10.go and internal/reader/atom/atom_10_adapter.go
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The Atom 1.0 adapter: the normalized model filled from the tree the reader builds.
///
/// The reference reads this format through the `atom10Feed` struct, and the chains below match the
/// tree against the namespaces its field tags name. `DefaultSpace` is not set for this format, so a
/// name with no prefix resolves to what the document declares, and to nothing when it declares
/// none; every tag that names a namespace is matched as written, and a tag that names none matches
/// any namespace. A single-value field takes the last element that matches at its own level,
/// because the reference assigns the field for every match.
///
/// The two ways the Text construct is read do not agree, which is why the title and the content are
/// read by two functions here: `body()` for the content and the description, and `title()` for the
/// title, which decodes a run that came from a CDATA section and reads the XHTML branch as markup.
/// Adapters do not sanitize content — sanitization is the next layer, so the content here is what
/// the format wrote.
enum Atom10Adapter {
    /// Reads a document and fills the model.
    ///
    /// `now` is the clock the date fallback reads, injected so the suite stays deterministic; the
    /// date parser itself reads no clock.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        let root = try XMLReader.read(data)

        // The base URL is used as it was given: this adapter does not trim it, which is where RSS
        // does.
        var feed = ParsedFeed(title: "", feedURL: baseURL, siteURL: baseURL, description: "", language: "",
            iconURL: "", ttlMinutes: 0, entries: [])

        let links = AtomLink.read(from: root, namespace: FeedNamespaces.atom)
        if let href = firstValue(AtomLink.firstLinkWithRelation(links, relation: "self")),
            let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: href) {
            feed.feedURL = absolute
        }
        if let href = firstValue(AtomLink.originalLink(links)),
            let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: href) {
            feed.siteURL = absolute
        }

        feed.title = body(field(root, local: "title", namespace: FeedNamespaces.atom))
        if feed.title.isEmpty { feed.title = feed.siteURL }

        feed.description = body(field(root, local: "subtitle", namespace: FeedNamespaces.atom))
        feed.language = Language.normalize(xmlLang(root))

        feed.iconURL = icon(root: root, siteURL: feed.siteURL)

        let feedAuthors = AtomPerson.read(from: root, namespace: FeedNamespaces.atom)
        let feedTags = categoryNames(root, namespace: FeedNamespaces.atom)

        for item in root.children(local: "entry", namespace: FeedNamespaces.atom) {
            feed.entries.append(entry(item: item, feed: feed, feedAuthors: feedAuthors, feedTags: feedTags,
                now: now))
        }

        return feed
    }

    /// One entry, assembled in the order the reference assembles it, because the later steps read
    /// what the earlier ones wrote: the URL before the content, the content before the title, and
    /// the title before the hash.
    private static func entry(item: XMLElement, feed: ParsedFeed, feedAuthors: [AtomPerson],
        feedTags: [String], now: ParsedDate) -> ParsedEntry {
        var entry = ParsedEntry(hash: "", title: "", url: "", commentsURL: "", author: "", content: "",
            language: "", date: now, tags: [], enclosures: [], readingTimeMinutes: 0)

        let links = AtomLink.read(from: item, namespace: FeedNamespaces.atom)
        let groups = MediaRules.elements(item, local: "group")
        let id = text(item, local: "id", namespace: FeedNamespaces.atom)

        entry.url = AtomLink.originalLink(links)
        if !entry.url.isEmpty {
            if let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL, relative: entry.url) {
                entry.url = absolute
            }
        }
        if entry.url.isEmpty {
            // With no link the ID is used when it is an absolute URL, otherwise the site URL.
            entry.url = URLRules.isAbsoluteURL(id) ? id : feed.siteURL
        }

        entry.content = body(field(item, local: "content", namespace: FeedNamespaces.atom))
        if entry.content.isEmpty {
            entry.content = body(field(item, local: "summary", namespace: FeedNamespaces.atom))
            if entry.content.isEmpty { entry.content = MediaRules.firstDescription(scope: item, groups: groups) }
        }

        entry.title = title(field(item, local: "title", namespace: FeedNamespaces.atom))
        if entry.title.isEmpty {
            entry.title = TruncateHTML.truncate(entry.content, limit: 100)
            if entry.title.isEmpty { entry.title = entry.url }
        }

        // `xml:lang` applies to the whole subtree it is declared on, so an entry without its own
        // value inherits the feed's; here that is the adapter's own fallback rather than a walk up
        // the tree.
        entry.language = Language.normalize(xmlLang(item))
        if entry.language.isEmpty { entry.language = feed.language }

        var names = SortedNames()
        for person in AtomPerson.read(from: item, namespace: FeedNamespaces.atom) { names.insert(person.personName) }
        let authors = names.names.isEmpty ? namesFor(feedAuthors) : names.names
        entry.author = authors.joined(separator: ", ")

        entry.date = date(item: item, now: now)
        entry.tags = categoryNames(item, namespace: FeedNamespaces.atom)
        if entry.tags.isEmpty { entry.tags = feedTags }

        // A link with this relation and no type is the assumed Atom type, which the gate does not
        // accept; only an absolute URL is kept. See https://tools.ietf.org/html/rfc4685#section-4.
        let comments = AtomLink.firstLinkWithRelationAndType(links, relation: "replies",
            contentTypes: ["text/html", "application/xhtml+xml"])
        if URLRules.isAbsoluteURL(comments) { entry.commentsURL = comments }

        for value in [id, AtomLink.originalLink(links)] {
            if value.isEmpty { continue }
            entry.hash = Hashes.sha256(value)
            break
        }

        entry.enclosures = enclosures(item: item, groups: groups, links: links, siteURL: feed.siteURL)

        return entry
    }

    // MARK: - The two ways the Text construct is read

    /// `body()`: the XHTML branch reads the div the element has, and any other type reads the
    /// character data at the element's own level; the trim comes after the branch.
    private static func body(_ element: XMLElement?) -> String {
        guard let element else { return "" }
        let value = AtomLink.equalFold(element.attribute(local: "type") ?? "", "xhtml")
            ? xhtmlContent(element) : element.text
        return UnicodeSpace.trim(value)
    }

    /// `title()`: the XHTML branch as above, then the CDATA branch, which decodes what the reader
    /// left as it was read, and otherwise the character data as the reader decoded it.
    private static func title(_ element: XMLElement?) -> String {
        guard let element else { return "" }

        let value: String
        if AtomLink.equalFold(element.attribute(local: "type") ?? "", "xhtml") {
            value = xhtmlContent(element)
        } else if element.innerMarkup.contains("<![CDATA[") {
            value = HTMLEntities.decode(element.text, attribute: false)
        } else {
            value = element.text
        }
        return UnicodeSpace.trim(value)
    }

    /// `xhtmlContent()`: the div in the XHTML namespace, or the element's own content when there is
    /// none.
    private static func xhtmlContent(_ element: XMLElement) -> String {
        field(element, local: "div", namespace: FeedNamespaces.xhtml)?.innerMarkup ?? element.innerMarkup
    }

    // MARK: - The chains the reference walks

    /// The icon is `icon`, then `logo`, resolved against the site URL rather than the base URL, and
    /// the first value that resolves is the one written.
    private static func icon(root: XMLElement, siteURL: String) -> String {
        for value in [text(root, local: "icon", namespace: FeedNamespaces.atom),
            text(root, local: "logo", namespace: FeedNamespaces.atom)] {
            let trimmed = UnicodeSpace.trim(value)
            if trimmed.isEmpty { continue }
            if let absolute = try? URLResolution.resolveToAbsolute(base: siteURL, relative: trimmed) {
                return absolute
            }
        }
        return ""
    }

    private static func enclosures(item: XMLElement, groups: [XMLElement], links: [AtomLink],
        siteURL: String) -> [ParsedEnclosure] {
        // The Atom thumbnails are the one group the reference compares before it resolves, which is
        // the difference `AtomMediaTests` pins; every other group compares the resolved value.
        let candidates = MediaRules.grouped(item, groups, local: "thumbnail")
            .map { MediaRules.thumbnail($0, comparedBeforeResolution: true) }
            + AtomLink.linksWithRelation(links, relation: "enclosure").map {
                MediaRules.Candidate(url: UnicodeSpace.trim($0.href), mimeType: $0.type,
                    size: Int($0.length) ?? 0, dropsWhenUnresolvable: true)
            }
            + MediaRules.grouped(item, groups, local: "content").map(MediaRules.content)
            + MediaRules.grouped(item, groups, local: "peerLink").map(MediaRules.peerLink)
        return MediaRules.enclosures(siteURL: siteURL, candidates: candidates)
    }

    /// `published`, then `updated`. A value that is empty or cannot be read is skipped rather than
    /// ending the chain, and a chain that reads nothing answers the clock.
    private static func date(item: XMLElement, now: ParsedDate) -> ParsedDate {
        for value in [text(item, local: "published", namespace: FeedNamespaces.atom),
            text(item, local: "updated", namespace: FeedNamespaces.atom)] {
            let trimmed = UnicodeSpace.trim(value)
            if trimmed.isEmpty { continue }
            if let parsed = try? FeedDateParser.parse(trimmed) { return parsed }
        }
        return now
    }

    /// `atomCategory.name()`: the label, then the term, each trimmed on its own, and a name that is
    /// empty is not inserted at all.
    private static func categoryNames(_ scope: XMLElement, namespace: String) -> [String] {
        var names = SortedNames()
        for category in scope.children(local: "category", namespace: namespace) {
            let label = UnicodeSpace.trim(category.attribute(local: "label") ?? "")
            names.insert(label.isEmpty ? UnicodeSpace.trim(category.attribute(local: "term") ?? "") : label)
        }
        return names.names
    }

    private static func namesFor(_ persons: [AtomPerson]) -> [String] {
        var names = SortedNames()
        for person in persons { names.insert(person.personName) }
        return names.names
    }

    /// `xml:lang` as the field tag names it: the XML namespace, so an attribute from another
    /// namespace, or one with no namespace at all, does not match.
    private static func xmlLang(_ element: XMLElement) -> String {
        element.attribute(local: "lang", namespace: FeedNamespaces.xml) ?? ""
    }

    // MARK: - Reading the tree

    private static func field(_ scope: XMLElement, local: String, namespace: String) -> XMLElement? {
        scope.children(local: local, namespace: namespace).last
    }

    /// The value a model field tagged `",chardata"` reads: the character data at the element's own
    /// level, as the reader decoded it.
    private static func text(_ scope: XMLElement, local: String, namespace: String) -> String {
        field(scope, local: local, namespace: namespace)?.text ?? ""
    }

    private static func firstValue(_ value: String) -> String? { value.isEmpty ? nil : value }
}
