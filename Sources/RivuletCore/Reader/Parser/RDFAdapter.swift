// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/rdf/adapter.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The RDF (RSS 1.0) adapter: the normalized model filled from the tree the reader builds.
///
/// The reference reads this format through the `rdf` struct, and the chains below match the tree
/// against the namespaces its field tags name. The channel and the items are direct children of the
/// root, because that is the shape the struct has, and the only tag that names a namespace is the item
/// title, which names the RSS 1.0 one; a tag that names no namespace matches any namespace.
/// `DefaultSpace` is not set for this format, so a name with no prefix resolves to what the document
/// declares, and to nothing when it declares none.
///
/// The fields the reference's structs have are the fields this adapter writes, so nothing here reads the
/// icon, the cache lifetime, the tags, the enclosures, the comments or the reading time, and content is
/// not sanitized — sanitization is the next layer.
enum RDFAdapter {
    /// Reads a document and fills the model.
    ///
    /// `now` is the clock the date fallback reads, injected so the suite stays deterministic; the date
    /// parser itself reads no clock.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        let root = try XMLReader.read(data)
        let channel = field(root, local: "channel")

        var feed = ParsedFeed(
            title: StripTags.strip(text(channel, local: "title")),
            feedURL: trimmed(baseURL),
            siteURL: trimmed(text(channel, local: "link")),
            description: trimmed(text(channel, local: "description")),
            language: Language.normalize(text(channel, local: "language", namespace: FeedNamespaces.dublinCore)),
            iconURL: "",
            ttlMinutes: 0,
            entries: []
        )

        // The title fallback is the base URL as the reference received it, not as it trims it for the
        // feed URL, and it is the base URL rather than the site URL, which is what RSS falls back to.
        if feed.title.isEmpty { feed.title = baseURL }

        // The site URL is resolved against the feed URL, and the entries are resolved against the site
        // URL, so the site URL is the base for the entry chain.
        if let absolute = try? URLResolution.resolveToAbsolute(base: feed.feedURL, relative: feed.siteURL) {
            feed.siteURL = absolute
        }

        for item in fields(root, local: "item") {
            feed.entries.append(entry(item: item, channel: channel, feed: feed, now: now))
        }

        return feed
    }

    /// One entry, assembled in the order the reference assembles it, because the later steps read what
    /// the earlier ones wrote: the URL before the title, and the title and the content before the hash.
    private static func entry(item: XMLElement, channel: XMLElement?, feed: ParsedFeed, now: ParsedDate)
        -> ParsedEntry {
        var entry = ParsedEntry(hash: "", title: "", url: "", commentsURL: "", author: "", content: "",
            language: "", date: now, tags: [], enclosures: [], readingTimeMinutes: 0)

        // The link is trimmed before anything reads it, and the hash reads that same trimmed value.
        let itemLink = trimmed(text(item, local: "link"))

        if itemLink.isEmpty {
            entry.url = feed.siteURL
        } else if let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL, relative: itemLink) {
            entry.url = absolute
        } else {
            entry.url = itemLink
        }

        // The item title is read first, so it wins over `dc:title`, which is the other way round from
        // RSS, and the value is decoded once on top of what the tokenizer decoded.
        for value in [text(item, local: "title", namespace: FeedNamespaces.rss10),
                      text(item, local: "title", namespace: FeedNamespaces.dublinCore)] {
            let candidate = trimmed(value)
            if candidate.isEmpty { continue }
            entry.title = decoded(candidate)
            break
        }
        if entry.title.isEmpty { entry.title = entry.url }

        entry.content = firstNonEmpty([text(item, local: "encoded", namespace: FeedNamespaces.contentModule),
            text(item, local: "description")])

        // The hash reads the values as the tokens read them, not as the title chain trims them, and the
        // link it reads is the one before it is resolved.
        let hashValue = itemLink.isEmpty
            ? text(item, local: "title", namespace: FeedNamespaces.rss10) + text(item, local: "description")
            : itemLink
        entry.hash = Hashes.sha256(hashValue)

        let dublinCoreDate = text(item, local: "date", namespace: FeedNamespaces.dublinCore)
        entry.date = dublinCoreDate.isEmpty ? now : (try? FeedDateParser.parse(dublinCoreDate)) ?? now

        let creator = firstNonEmpty([text(item, local: "creator", namespace: FeedNamespaces.dublinCore),
            text(channel, local: "creator", namespace: FeedNamespaces.dublinCore)])
        if !creator.isEmpty { entry.author = StripTags.strip(creator) }

        // Items are part of the channel's content, so an entry inherits the channel language.
        entry.language = Language.normalize(text(item, local: "language", namespace: FeedNamespaces.dublinCore))
        if entry.language.isEmpty { entry.language = feed.language }

        return entry
    }

    // MARK: - Reading the tree

    private static func fields(_ scope: XMLElement?, local: String, namespace: String = "") -> [XMLElement] {
        scope?.children(local: local, namespace: namespace) ?? []
    }

    /// The element a model field reads. The reference assigns the field for every element that matches at
    /// the element's own level, so the last occurrence wins, which is why this takes the last match rather
    /// than the first the tree's own `child` answers.
    private static func field(_ scope: XMLElement?, local: String, namespace: String = "") -> XMLElement? {
        fields(scope, local: local, namespace: namespace).last
    }

    /// The value a model field tagged `",chardata"` reads: the character data at the element's own level.
    private static func text(_ scope: XMLElement?, local: String, namespace: String = "") -> String {
        field(scope, local: local, namespace: namespace)?.text ?? ""
    }

    private static func firstNonEmpty(_ values: [String]) -> String { values.first { !$0.isEmpty } ?? "" }

    private static func trimmed(_ value: String) -> String { UnicodeSpace.trim(value) }

    /// `html.UnescapeString`, the pass the adapter reads through on top of what the tokenizer decoded.
    private static func decoded(_ value: String) -> String { HTMLEntities.decode(value, attribute: false) }
}
