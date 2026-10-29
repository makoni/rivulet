// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/rss/adapter.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The RSS adapter: the normalized model filled from the tree the reader builds.
///
/// The reference fills the same values through the `rss` struct and its field tags, so the chains below
/// match the tree against the namespaces those tags name: a tag that names no namespace matches any
/// namespace, and a name with no prefix resolves to the format's default space. Adapters do not sanitize
/// content — sanitization is the next layer. The two text-layer rules used here are the ones the
/// reference applies at this point: `TruncateHTML` for the title fallback and `StripTags` for an author.
enum RSSAdapter {
    /// Reads a document and fills the model.
    ///
    /// `now` is the clock the date fallback reads, injected so the suite stays deterministic; the date
    /// parser itself reads no clock.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        let root = try XMLReader.read(data)
        let channel = field(root, local: "channel", namespace: defaultSpace)

        var feed = ParsedFeed(
            title: decoded(trimmed(text(channel, local: "title", namespace: defaultSpace))),
            feedURL: trimmed(baseURL),
            siteURL: trimmed(text(channel, local: "link", namespace: defaultSpace)),
            description: trimmed(text(channel, local: "description", namespace: defaultSpace)),
            language: Language.normalize(text(channel, local: "language", namespace: defaultSpace)),
            iconURL: "",
            ttlMinutes: 0,
            entries: []
        )

        // Hybrid feeds declare the channel language with `dc:language` instead of `language`.
        let dublinCoreLanguage = text(channel, local: "language", namespace: FeedNamespaces.dublinCore)
        if feed.language.isEmpty { feed.language = Language.normalize(dublinCoreLanguage) }

        if let absolute = try? URLResolution.resolveToAbsolute(base: baseURL, relative: feed.siteURL) {
            feed.siteURL = absolute
        }

        for link in fields(channel, local: "link", namespace: FeedNamespaces.atom) {
            // The reference trims the href before the check, so the value it resolves is the trimmed one.
            let href = trimmed(attribute(link, local: "href"))
            if href.isEmpty || attribute(link, local: "rel") != "self" { continue }
            if let absolute = try? URLResolution.resolveToAbsolute(base: feed.feedURL, relative: href) {
                feed.feedURL = absolute
                break
            }
        }

        if feed.title.isEmpty { feed.title = feed.siteURL }

        if let ttl = Int(text(channel, local: "ttl", namespace: defaultSpace)) { feed.ttlMinutes = ttl }

        // The reference reads the image URL as a child element, not as an attribute.
        if let image = field(channel, local: "image", namespace: defaultSpace),
            let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL,
                relative: text(image, local: "url", namespace: "")) {
            feed.iconURL = absolute
        }

        var seenGUIDs: [String: Int] = [:]
        for item in fields(channel, local: "item", namespace: defaultSpace) {
            feed.entries.append(entry(item: item, channel: channel, feed: feed, now: now, seenGUIDs: &seenGUIDs))
        }

        return feed
    }

    /// One entry, assembled in the order the reference assembles it, because the later steps read what the
    /// earlier ones wrote: content and enclosures before the URL, the URL before the title, and the title
    /// before the hash.
    private static func entry(item: XMLElement, channel: XMLElement?, feed: ParsedFeed, now: ParsedDate,
        seenGUIDs: inout [String: Int]) -> ParsedEntry {
        var entry = ParsedEntry(hash: "", title: "", url: "", commentsURL: "", author: "", content: "",
            language: "", date: now, tags: [], enclosures: [], readingTimeMinutes: 0)

        entry.date = findEntryDate(item: item, now: now)
        entry.content = findEntryContent(item: item)
        entry.enclosures = RSSMedia.enclosures(item: item, siteURL: feed.siteURL)

        let entryURL = findEntryURL(item: item)
        if !entryURL.isEmpty {
            entry.url = entryURL
            if let absolute = try? URLResolution.resolveToAbsolute(base: feed.siteURL, relative: entryURL) {
                entry.url = absolute
            }
        }

        if entry.url.isEmpty {
            // Fallback to the site URL, then to the first enclosure URL.
            entry.url = feed.siteURL
            if let first = entry.enclosures.first, !first.url.isEmpty { entry.url = first.url }
        }

        entry.title = findEntryTitle(item: item)
        if entry.title.isEmpty {
            entry.title = TruncateHTML.truncate(entry.content, limit: 100)
            if entry.title.isEmpty { entry.title = entry.url }
        }

        entry.author = findEntryAuthor(item: item)
        if entry.author.isEmpty { entry.author = findFeedAuthor(channel: channel) }

        // Items are part of the channel's content, so an entry inherits the channel language.
        entry.language = Language.normalize(text(item, local: "language", namespace: FeedNamespaces.dublinCore))
        if entry.language.isEmpty { entry.language = feed.language }

        entry.hash = entryHash(item: item, entryURL: entryURL, entry: entry, seenGUIDs: &seenGUIDs)

        let comments = trimmed(text(item, local: "comments", namespace: defaultSpace))
        if !comments.isEmpty, URLRules.isAbsoluteURL(comments) { entry.commentsURL = comments }

        if let minutes = durationInMinutes(text(item, local: "duration", namespace: FeedNamespaces.itunes)) {
            entry.readingTimeMinutes = minutes
        }

        entry.tags = findEntryTags(item: item)
        if entry.tags.isEmpty { entry.tags = findFeedTags(channel: channel) }

        return entry
    }

    // MARK: - The chains the reference walks

    /// `findEntryTitle`: the character data the title element collects, `dc:title` wins over it, and the
    /// value is decoded twice — which is what separates an entry title from a feed title.
    private static func findEntryTitle(item: XMLElement) -> String {
        var title = innerContent(item, local: "title", namespace: defaultSpace)
        let dublinCoreTitle = text(item, local: "title", namespace: FeedNamespaces.dublinCore)
        if !dublinCoreTitle.isEmpty { title = dublinCoreTitle }
        return decoded(decoded(trimmed(title)))
    }

    /// `findEntryURL`: the FeedBurner original link, the item link, an atom link with this relation or no
    /// relation, then the GUID when it is a permalink — which is the default for `isPermaLink`.
    private static func findEntryURL(item: XMLElement) -> String {
        for value in [text(item, local: "origLink", namespace: FeedNamespaces.feedBurner),
                      text(item, local: "link", namespace: defaultSpace)] {
            if !value.isEmpty { return trimmed(value) }
        }

        for link in fields(item, local: "link", namespace: FeedNamespaces.atom) {
            let href = attribute(link, local: "href")
            if href.isEmpty { continue }
            let relation = attribute(link, local: "rel")
            if relation.isEmpty || equalFold(relation, "alternate") { return trimmed(href) }
        }

        let isPermaLink = attribute(field(item, local: "guid", namespace: defaultSpace), local: "isPermaLink")
        if isPermaLink == "true" || isPermaLink.isEmpty {
            return trimmed(text(item, local: "guid", namespace: defaultSpace))
        }
        return ""
    }

    /// `findEntryContent`, in the order the reference reads it. `media:description` is not part of this
    /// format's content chain.
    private static func findEntryContent(item: XMLElement) -> String {
        for value in [text(item, local: "encoded", namespace: FeedNamespaces.contentModule),
                      text(item, local: "description", namespace: defaultSpace),
                      text(item, local: "description", namespace: FeedNamespaces.googlePlay),
                      text(item, local: "summary", namespace: FeedNamespaces.itunes),
                      text(item, local: "subtitle", namespace: FeedNamespaces.itunes)] {
            if !value.isEmpty { return value }
        }
        return ""
    }

    /// `findEntryDate`: `dc:date` wins over `pubDate`, and a value that is empty or cannot be read is the
    /// clock, which is what the reference logs a debug line for.
    private static func findEntryDate(item: XMLElement, now: ParsedDate) -> ParsedDate {
        var value = text(item, local: "pubDate", namespace: defaultSpace)
        let dublinCoreDate = text(item, local: "date", namespace: FeedNamespaces.dublinCore)
        if !dublinCoreDate.isEmpty { value = dublinCoreDate }

        let trimmed = trimmed(value)
        return trimmed.isEmpty ? now : (try? FeedDateParser.parse(trimmed)) ?? now
    }

    /// `findEntryAuthor`. The CDATA branch reads the character data, and the branch after it reads the
    /// inner markup, which is why an author that is a link is not read as the link's text alone.
    private static func findEntryAuthor(item: XMLElement) -> String {
        let author = field(item, local: "author", namespace: defaultSpace)
        let inner = author?.innerMarkup ?? ""

        let name = firstNonEmpty([
            text(item, local: "author", namespace: FeedNamespaces.googlePlay),
            text(item, local: "author", namespace: FeedNamespaces.itunes),
            text(item, local: "creator", namespace: FeedNamespaces.dublinCore),
            personName(field(item, local: "author", namespace: FeedNamespaces.atom)),
        ])
        if !name.isEmpty { return StripTags.strip(name) }

        if inner.contains("<![CDATA[") { return StripTags.strip(author?.text ?? "") }
        return inner.isEmpty ? "" : StripTags.strip(inner)
    }

    /// `findFeedAuthor`, the author an entry falls back to, in the order the reference reads it.
    private static func findFeedAuthor(channel: XMLElement?) -> String {
        let name = firstNonEmpty([
            text(channel, local: "author", namespace: FeedNamespaces.itunes),
            text(channel, local: "author", namespace: FeedNamespaces.googlePlay),
            ownerString(field(channel, local: "owner", namespace: FeedNamespaces.itunes)),
            text(channel, local: "managingEditor", namespace: defaultSpace),
            text(channel, local: "webMaster", namespace: defaultSpace),
        ])
        return name.isEmpty ? "" : StripTags.strip(name)
    }

    /// `PersonName`: the name, then the email, each trimmed on its own.
    private static func personName(_ person: XMLElement?) -> String {
        let name = trimmed(text(person, local: "name", namespace: ""))
        return name.isEmpty ? trimmed(text(person, local: "email", namespace: "")) : name
    }

    /// `ItunesOwnerElement.String()`, which is not the rule above: the choice is made on the values as
    /// they were read, and only the one chosen is trimmed, so a name that is only whitespace wins and
    /// answers empty.
    private static func ownerString(_ owner: XMLElement?) -> String {
        let name = text(owner, local: "name", namespace: "")
        return trimmed(name.isEmpty ? text(owner, local: "email", namespace: "") : name)
    }

    /// `findEntryTags`: the item's categories, then the media categories that carry a label.
    private static func findEntryTags(item: XMLElement) -> [String] {
        var names = SortedNames()
        for category in fields(item, local: "category", namespace: defaultSpace) {
            names.insert(trimmed(category.text))
        }
        for category in fields(item, local: "category", namespace: FeedNamespaces.media) {
            names.insert(trimmed(attribute(category, local: "label")))
        }
        return names.names
    }

    /// `findFeedTags`, the tags an entry falls back to. The nested `itunes:category` reads its parent and
    /// every subcategory.
    private static func findFeedTags(channel: XMLElement?) -> [String] {
        var names = SortedNames()
        for category in fields(channel, local: "category", namespace: defaultSpace) {
            names.insert(trimmed(category.text))
        }
        for category in fields(channel, local: "category", namespace: FeedNamespaces.itunes) {
            var element: XMLElement? = category
            while let current = element {
                names.insert(trimmed(attribute(current, local: "text")))
                element = current.children(local: "category", namespace: FeedNamespaces.itunes).first
            }
        }
        names.insert(trimmed(attribute(field(channel, local: "category", namespace: FeedNamespaces.googlePlay),
            local: "text")))
        return names.names
    }

    /// The entry identity. The reference keeps the first occurrence of a GUID stable so entries already
    /// stored still match, and disambiguates a later collision with the entry URL or, as the last resort,
    /// the item position.
    private static func entryHash(item: XMLElement, entryURL: String, entry: ParsedEntry,
        seenGUIDs: inout [String: Int]) -> String {
        let guid = text(item, local: "guid", namespace: defaultSpace)

        if !guid.isEmpty {
            let seen = seenGUIDs[guid, default: 0]
            seenGUIDs[guid] = seen + 1
            if seen == 0 { return Hashes.sha256(guid) }
            if !entry.url.isEmpty { return Hashes.sha256(guid + "|" + entry.url) }
            return Hashes.sha256(guid + "|" + String(seen))
        }

        // The URL branch hashes the URL as `findEntryURL` returned it, before it is resolved.
        if !entryURL.isEmpty { return Hashes.sha256(entryURL) }
        return Hashes.sha256(entry.title + entry.content)
    }

    /// `getDurationInMinutes`: each part is weighted by its position and the sum is divided by 60. More
    /// than three parts, or a part that is not a number, is not a duration.
    private static func durationInMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 3 { return nil }

        var seconds = 0
        for (index, part) in parts.enumerated() {
            guard let number = Int(part) else { return nil }
            seconds += Int(pow(60.0, Double(parts.count - index - 1))) * number
        }
        return seconds / 60
    }

    // MARK: - Reading the tree

    /// The default space `translate` applies to a name with no prefix, which the tree has already resolved
    /// for a declared default namespace.
    private static let defaultSpace = FeedNamespaces.rssDefault

    private static func fields(_ scope: XMLElement?, local: String, namespace: String) -> [XMLElement] {
        scope?.children(local: local, namespace: namespace, defaultSpace: defaultSpace) ?? []
    }

    private static func field(_ scope: XMLElement?, local: String, namespace: String) -> XMLElement? {
        fields(scope, local: local, namespace: namespace).first
    }

    /// The value a model field tagged `",chardata"` reads: the character data at the element's own level.
    private static func text(_ scope: XMLElement?, local: String, namespace: String) -> String {
        field(scope, local: local, namespace: namespace)?.text ?? ""
    }

    /// The value the reference's `innerContent` type collects, which is every character token inside the
    /// element.
    private static func innerContent(_ scope: XMLElement?, local: String, namespace: String) -> String {
        field(scope, local: local, namespace: namespace)?.innerContent ?? ""
    }

    private static func attribute(_ scope: XMLElement?, local: String, namespace: String = "") -> String {
        scope?.attribute(local: local, namespace: namespace) ?? ""
    }

    private static func firstNonEmpty(_ values: [String]) -> String { values.first { !$0.isEmpty } ?? "" }

    private static func trimmed(_ value: String) -> String { UnicodeSpace.trim(value) }

    /// `html.UnescapeString`, the pass the adapters read through on top of what the tokenizer decoded.
    private static func decoded(_ value: String) -> String { HTMLEntities.decode(value, attribute: false) }

    /// The fold `strings.EqualFold` does on the ASCII range, which is its fast path. The reference goes
    /// past ASCII through `unicode.SimpleFold`, so a relation such as `aſternate` matches there and not
    /// here — recorded in `docs/parity.md`.
    private static func equalFold(_ left: String, _ right: String) -> Bool {
        func fold(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }
        return [UInt8](left.utf8).map(fold) == [UInt8](right.utf8).map(fold)
    }
}
