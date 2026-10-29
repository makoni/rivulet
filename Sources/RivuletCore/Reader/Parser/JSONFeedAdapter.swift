// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/json/adapter.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The JSON Feed adapter: the normalized model filled from the tree the reader builds.
///
/// The reference fills the same values through the `JSONFeed` struct and its field tags, so the
/// chains below read the tree through the field table `JSONFieldRead` keeps. Adapters do not
/// sanitize content — sanitization is the next layer — so the content here is what the format
/// wrote, and the two text rules the reference applies at this point are the escape
/// `html.EscapeString` does for the plain-text fields and `TruncateHTML` for the title fallback.
///
/// The clock the date fallback reads is injected as a parameter, because nothing else in this layer
/// reads one; the date parser itself reads no clock.
enum JSONFeedAdapter {
    /// Reads a document and fills the model.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        let document = try JSONFieldRead.read(data)

        var feed = ParsedFeed(title: trimmed(document.title), feedURL: trimmed(document.feedURL),
            siteURL: trimmed(document.homePageURL), description: trimmed(document.description),
            language: Language.normalize(document.language), iconURL: "", ttlMinutes: 0, entries: [])

        if feed.feedURL.isEmpty { feed.feedURL = trimmed(baseURL) }

        // Fallback to the feed URL if the site URL is empty.
        if feed.siteURL.isEmpty { feed.siteURL = feed.feedURL }

        if let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: feed.feedURL) {
            feed.feedURL = absolute
        }
        if let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: feed.siteURL) {
            feed.siteURL = absolute
        }

        // Fallback to the site URL if the title is empty.
        if feed.title.isEmpty { feed.title = feed.siteURL }

        // The favicon is looked at first, and the walk stops at the first value it can resolve.
        for value in [document.faviconURL, document.iconURL] {
            let iconURL = trimmed(value)
            if iconURL.isEmpty { continue }
            if let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL, relative: iconURL) {
                feed.iconURL = absolute
                break
            }
        }

        for item in document.items {
            feed.entries.append(entry(item: item, document: document, feed: feed, now: now))
        }

        return feed
    }

    /// The body of `BuildFeed`'s loop, with the fields in the order the reference writes them.
    private static func entry(item: JSONFieldRead.Item, document: JSONFieldRead.Feed, feed: ParsedFeed,
        now: ParsedDate) -> ParsedEntry {
        var entry = ParsedEntry(hash: "", title: "", url: "", commentsURL: "", author: "", content: "",
            language: "", date: now, tags: [], enclosures: [], readingTimeMinutes: 0)

        entry.language = entryLanguage(item: item, feed: feed)
        entry.url = entryURL(item: item, siteURL: feed.siteURL)
        entry.title = entryTitle(item: item, entryURL: entry.url)
        entry.content = entryContent(item: item)
        entry.date = entryDate(item: item, now: now)
        entry.author = entryAuthor(item: item, document: document)
        entry.enclosures = entryEnclosures(item: item, siteURL: feed.siteURL)
        entry.tags = entryTags(item: item)
        entry.hash = entryHash(item: item)

        return entry
    }

    // MARK: - The chains the reference walks

    /// The entry language. Per the spec an item declares a language only when it differs from the
    /// feed's, so an empty one is the feed's, already normalized.
    private static func entryLanguage(item: JSONFieldRead.Item, feed: ParsedFeed) -> String {
        let language = Language.normalize(item.language)
        return language.isEmpty ? feed.language : language
    }

    /// `url` then `external_url`, each trimmed on its own, and the first value that resolves is
    /// what the entry gets. A value that cannot be resolved is skipped, which is what the reference
    /// logs for.
    private static func entryURL(item: JSONFieldRead.Item, siteURL: String) -> String {
        for value in [item.url, item.externalURL] {
            let value = trimmed(value)
            if value.isEmpty { continue }
            if let absolute = try? URLResolution.resolveToAbsolute(base: siteURL, relative: value) {
                return absolute
            }
        }
        return ""
    }

    /// The title as it was read, then the three fallback values through `TruncateHTML` at the limit
    /// the reference uses, and then the entry URL.
    private static func entryTitle(item: JSONFieldRead.Item, entryURL: String) -> String {
        let title = trimmed(item.title)
        if !title.isEmpty { return title }

        for value in [item.summary, item.contentText, item.contentHTML] {
            let truncated = TruncateHTML.truncate(value, limit: 100)
            if truncated.isEmpty { continue }
            return truncated
        }

        return entryURL
    }

    /// `content_html` is HTML, but `content_text` and `summary` are plain text per the 1.1 spec, so
    /// they are escaped before being stored, which is what keeps markup-like characters.
    private static func entryContent(item: JSONFieldRead.Item) -> String {
        let contentHTML = trimmed(item.contentHTML)
        if !contentHTML.isEmpty { return contentHTML }

        let contentText = trimmed(item.contentText)
        if !contentText.isEmpty { return HTMLEscape.escapeString(contentText) }

        let summary = trimmed(item.summary)
        return summary.isEmpty ? "" : HTMLEscape.escapeString(summary)
    }

    /// `date_published` then `date_modified`, and a value that cannot be read moves on to the next
    /// rather than failing the document, which is what the reference logs a debug line for.
    private static func entryDate(item: JSONFieldRead.Item, now: ParsedDate) -> ParsedDate {
        for value in [item.datePublished, item.dateModified] {
            let value = trimmed(value)
            if value.isEmpty { continue }
            if let parsed = try? FeedDateParser.parse(value) { return parsed }
        }
        return now
    }

    /// The four places the format declares an author, in the order the reference appends them, with
    /// the name rule `JSONAuthor.name()` applies.
    private static func entryAuthor(item: JSONFieldRead.Item, document: JSONFieldRead.Feed) -> String {
        var names = SortedNames()
        for person in document.authors { names.insert(trimmed(person.name)) }
        for person in item.authors { names.insert(trimmed(person.name)) }
        for person in [item.author, document.author] { names.insert(trimmed(person.name)) }
        return names.names.joined(separator: ", ")
    }

    /// The attachments, in the order the document wrote them, with the URL resolved against the
    /// site URL.
    private static func entryEnclosures(item: JSONFieldRead.Item, siteURL: String) -> [ParsedEnclosure] {
        var enclosures: [ParsedEnclosure] = []
        for attachment in item.attachments {
            let url = trimmed(attachment.url)
            if url.isEmpty { continue }
            guard let absolute = try? URLResolution.resolveToAbsolute(base: siteURL, relative: url) else {
                continue
            }
            enclosures.append(ParsedEnclosure(url: absolute, mimeType: attachment.mimeType,
                size: attachment.size))
        }
        return enclosures
    }

    /// The tags, trimmed and inserted in sorted position, which is what deduplicates them.
    private static func entryTags(item: JSONFieldRead.Item) -> [String] {
        var names = SortedNames()
        for tag in item.tags { names.insert(trimmed(tag)) }
        return names.names
    }

    /// The entry identity, the four values in the order the reference walks them, each trimmed on
    /// its own. The content value is the three fields concatenated as the shape holds them, not as
    /// the entry gets them, so it is not the escaped version.
    private static func entryHash(item: JSONFieldRead.Item) -> String {
        for value in [item.id, item.url, item.externalURL,
                      item.contentText + item.contentHTML + item.summary] {
            let value = trimmed(value)
            if value.isEmpty { continue }
            return Hashes.sha256(value)
        }
        return ""
    }

    private static func trimmed(_ value: String) -> String { UnicodeSpace.trim(value) }
}
