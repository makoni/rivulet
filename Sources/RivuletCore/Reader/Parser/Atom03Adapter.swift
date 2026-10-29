// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/atom/atom_03.go and internal/reader/atom/atom_03_adapter.go
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The Atom 0.3 adapter: the normalized model filled from the tree the reader builds.
///
/// This version is not the 1.0 one, so the rules are kept apart: the Content construct reads
/// through its `mode` attribute and then escapes what it got unless the type is already HTML, the
/// date chain is `issued`, `modified`, `created`, the author is one Person rather than a list, and
/// an entry has no ID-as-URL fallback. The feed fields name the 0.3 namespace while the entry
/// fields name none, so the two resolve differently, and `DefaultSpace` is not set for this format.
///
/// The fields the reference's struct has are the fields this adapter writes, so nothing here reads
/// the icon, the tags, the comments, the attachments or the reading time, and content is not
/// sanitized — sanitization is the layer after this one.
enum Atom03Adapter {
    /// Reads a document and fills the model.
    ///
    /// `now` is the clock the date fallback reads, injected so the suite stays deterministic; the
    /// date parser itself reads no clock. The version is what format detection answered for the
    /// root.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        let root = try XMLReader.read(data)

        var feed = ParsedFeed(title: "", feedURL: baseURL, siteURL: baseURL, description: "", language: "",
            iconURL: "", ttlMinutes: 0, entries: [])

        let feedNamespace = FeedNamespaces.atom03
        let links = AtomLink.read(from: root, namespace: feedNamespace)
        if let href = firstValue(AtomLink.firstLinkWithRelation(links, relation: "self")),
            let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: href) {
            feed.feedURL = absolute
        }
        if let href = firstValue(AtomLink.originalLink(links)),
            let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: href) {
            feed.siteURL = absolute
        }

        feed.title = content(field(root, local: "title", namespace: feedNamespace))
        if feed.title.isEmpty { feed.title = feed.siteURL }

        feed.language = Language.normalize(xmlLang(root))
        let feedAuthor = AtomPerson.read(from: root, namespace: feedNamespace).last

        for item in root.children(local: "entry", namespace: feedNamespace) {
            // The entry field tags name no namespace, so they match any namespace.
            feed.entries.append(entry(item: item, feed: feed, feedAuthor: feedAuthor, now: now))
        }

        return feed
    }

    /// One entry, assembled in the order the reference assembles it, because the later steps read
    /// what the earlier ones wrote: the URL before the content, the content before the title, and
    /// the title before the hash.
    private static func entry(item: XMLElement, feed: ParsedFeed, feedAuthor: AtomPerson?, now: ParsedDate)
        -> ParsedEntry {
        var entry = ParsedEntry(hash: "", title: "", url: "", commentsURL: "", author: "", content: "",
            language: "", date: now, tags: [], enclosures: [], readingTimeMinutes: 0)

        // `xml:lang` applies to the whole subtree it is declared on, so an entry without its own
        // value inherits the feed's; here that is the adapter's own fallback rather than a walk up
        // the tree.
        entry.language = Language.normalize(xmlLang(item))
        if entry.language.isEmpty { entry.language = feed.language }

        entry.url = AtomLink.originalLink(AtomLink.read(from: item, namespace: ""))
        if !entry.url.isEmpty,
            let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL, relative: entry.url) {
            entry.url = absolute
        }

        entry.content = content(field(item, local: "content", namespace: ""))
        if entry.content.isEmpty { entry.content = content(field(item, local: "summary", namespace: "")) }

        entry.title = content(field(item, local: "title", namespace: ""))
        if entry.title.isEmpty { entry.title = TruncateHTML.truncate(entry.content, limit: 100) }
        if entry.title.isEmpty { entry.title = entry.url }

        let person = AtomPerson.read(from: item, namespace: "").last
        let name = person?.personName ?? ""
        entry.author = name.isEmpty ? feedAuthor?.personName ?? "" : name

        entry.date = date(item: item, now: now)

        for value in [text(item, local: "id", namespace: ""), AtomLink.originalLink(AtomLink.read(from: item,
            namespace: ""))] {
            if value.isEmpty { continue }
            entry.hash = Hashes.sha256(value)
            break
        }

        return entry
    }

    // MARK: - The Content construct

    /// `content()`: the mode branch, then the escape, then the trim. The default mode is the
    /// character data rather than the markup, the type comparison is not a fold, and only
    /// `text/html` skips the escape.
    private static func content(_ element: XMLElement?) -> String {
        guard let element else { return "" }

        var value: String
        switch element.attribute(local: "mode") ?? "" {
        case "xml": value = element.innerMarkup
        case "base64": value = decodedBase64(element.text) ?? ""
        default: value = element.text
        }

        if element.attribute(local: "type") != "text/html" { value = HTMLEscape.escapeString(value) }
        return UnicodeSpace.trim(value)
    }

    /// `base64.StdEncoding.DecodeString`: the two newlines are skipped and anything else the
    /// alphabet does not have fails the read, which leaves the content empty rather than half-read.
    /// Go reports padding in a position this cannot check as an error, which is recorded in
    /// `docs/parity.md`.
    private static func decodedBase64(_ value: String) -> String? {
        let bytes = [UInt8](value.utf8).filter { $0 != 0x0A && $0 != 0x0D }
        guard let data = Data(base64Encoded: String(decoding: bytes, as: UTF8.self)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - The chains the reference walks

    /// `issued`, then `modified`, then `created`. A value that is empty or cannot be read is
    /// skipped rather than ending the chain, and a chain that reads nothing answers the clock.
    private static func date(item: XMLElement, now: ParsedDate) -> ParsedDate {
        for value in [text(item, local: "issued", namespace: ""), text(item, local: "modified", namespace: ""),
            text(item, local: "created", namespace: "")] {
            let trimmed = UnicodeSpace.trim(value)
            if trimmed.isEmpty { continue }
            if let parsed = try? FeedDateParser.parse(trimmed) { return parsed }
        }
        return now
    }

    /// `xml:lang` as the field tag names it: the XML namespace, so an attribute from another
    /// namespace, or one with no namespace at all, does not match.
    private static func xmlLang(_ element: XMLElement) -> String {
        element.attribute(local: "lang", namespace: FeedNamespaces.xml) ?? ""
    }

    // MARK: - Reading the tree

    /// A single-value field: the reference assigns the field for every element that matches at the
    /// element's own level, so the last occurrence wins.
    private static func field(_ scope: XMLElement, local: String, namespace: String) -> XMLElement? {
        scope.children(local: local, namespace: namespace).last
    }

    private static func text(_ scope: XMLElement, local: String, namespace: String) -> String {
        field(scope, local: local, namespace: namespace)?.text ?? ""
    }

    private static func firstValue(_ value: String) -> String? { value.isEmpty ? nil : value }
}
