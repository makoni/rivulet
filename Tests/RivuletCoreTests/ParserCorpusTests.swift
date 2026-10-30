// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import Testing
@testable import RivuletCore

/// The parser fixture corpus: the 8 fixtures read end to end against the reference's own output.
///
/// Upstream uses these files only as benchmark and fuzz inputs, so no Go test states what the
/// parse produces. The golden files in `Fixtures/parser/golden/` carry the values the reference
/// produces, written by running Miniflux v2.3.3 over these bytes with the clock fixed to UTC, and
/// the method is recorded in `docs/testing.md`. Every golden value is the reference's, never this
/// implementation's, so a failure here is a difference in the implementation under test, and
/// recording it in `docs/parity.md` is the only way a difference can stay.
///
/// Each golden line pins one value as `path = value`, and every golden value is the reference's,
/// never this implementation's. The paths are the fields the adapters write, plus `format`,
/// `version` and `entries`. A value that would break a line — content with newlines in it — is
/// written with `\n`, `\t`, `\r` and `\\`, and an empty value is written as `(empty)`. For the two
/// fixtures whose content is longer than the golden files keep readable, content is pinned as its
/// first 120 code points of the content as read, plus its SHA-256, which pins the whole of it; the
/// prefix is taken before the escaping, so a newline inside it is pinned as a newline and written
/// as `\n`. The zone name a date resolved to is not pinned, because the reference reads it through
/// the machine's tzdata; see `docs/parity.md`.
///
/// No case reads a clock, a locale or the network. The base URL a case uses is the one its golden
/// file was written with, stated at the call site, because the feed URL an adapter keeps is the
/// base URL when the document declares no self link.
@Suite struct ParserCorpusTests {
    private let clock = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    /// The prefix a content value longer than the golden files keep readable is pinned as.
    private static let pinnedPrefix = 120

    /// Each case names the fixture and the base URL its golden file was written with. The format is
    /// not carried here: the test detects it, because that is one of the values the golden pins.
    private static let corpus = [
        ("encoding_ISO-8859-1.xml", "https://example.org/feed.xml"),
        ("encoding_WINDOWS-1251.xml", "https://example.org/feed.xml"),
        ("large_atom.xml", "https://example.org/feed.atom"),
        ("large_rss.xml", "https://example.org/feed.xml"),
        ("no_encoding_ISO-8859-1.xml", "https://example.org/feed.xml"),
        ("rdf_UTF8.xml", "https://example.org/feed.rdf"),
        ("small_atom.xml", "https://example.org/feed.atom"),
        ("urdu_UTF8.xml", "https://example.org/feed.xml"),
    ]

    /// `TestParseFeed` over the corpus: the values the reference produces for each fixture.
    @Test(arguments: corpus) func fixtureMatchesItsGolden(fixture: String, baseURL: String) throws {
        let data = try Fixtures.data("parser/\(fixture)")
        let detected = FeedFormatDetector.detect(data)
        let feed = try parse(fixture: fixture, data: data, baseURL: baseURL, detected: detected)

        for (path, expected) in try golden(fixture: fixture) {
            #expect(value(for: path, from: feed, detected: detected) == expected,
                Comment("\(fixture): \(path)"))
        }
    }

    /// The dispatch `ParseFeed` makes: the format decides the adapter, and for Atom the version
    /// decides which one reads the document.
    private func parse(fixture: String, data: Data, baseURL: String, detected: DetectedFormat) throws
        -> ParsedFeed {
        switch detected.format {
        case .atom:
            return detected.version == "0.3"
                ? try Atom03Adapter.parse(baseURL: baseURL, data: data, now: clock)
                : try Atom10Adapter.parse(baseURL: baseURL, data: data, now: clock)
        case .rss: return try RSSAdapter.parse(baseURL: baseURL, data: data, now: clock)
        case .rdf: return try RDFAdapter.parse(baseURL: baseURL, data: data, now: clock)
        case .json: return try JSONFeedAdapter.parse(baseURL: baseURL, data: data, now: clock)
        case .unknown: throw UndetectedFormat(fixture: fixture)
        }
    }

    /// A fixture whose format the port cannot detect fails here rather than against a golden line.
    /// The typed "not a feed" error the reference returns is an open item in the plan, so the
    /// corpus cannot assert it yet.
    private struct UndetectedFormat: Error {
        let fixture: String
    }

    private func golden(fixture: String) throws -> [(path: String, value: String)] {
        let text = Fixtures.utf8(try Fixtures.data("parser/golden/\(fixture).golden.txt"))
        return text.split(separator: "\n").compactMap { line in
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            // The line is `path = value`, so the value keeps everything after the single space that
            // follows the separator: a value is never trimmed.
            let value = parts[1].hasPrefix(" ") ? String(parts[1].dropFirst()) : String(parts[1])
            return (String(parts[0].trimmingCharacters(in: .whitespaces)), value)
        }
    }

    /// One pinned path resolved against what the port produced, written the way the golden file
    /// writes it, so both sides compare the same shape.
    private func value(for path: String, from feed: ParsedFeed, detected: DetectedFormat) -> String {
        let parts = path.split(separator: ".")
        switch parts[0] {
        case "format": return escapeValue(detected.format.rawValue)
        case "version": return escapeValue(detected.version ?? "")
        case "entries": return escapeValue(String(feed.entries.count))
        case "feed": return escapeValue(feedField(parts[1], feed))
        default: return entryValue(parts, feed)
        }
    }

    private func feedField(_ name: Substring, _ feed: ParsedFeed) -> String {
        switch name {
        case "title": return feed.title
        case "feedURL": return feed.feedURL
        case "siteURL": return feed.siteURL
        case "description": return feed.description
        case "language": return feed.language
        case "iconURL": return feed.iconURL
        default: return String(feed.ttlMinutes)
        }
    }

    private func entryValue(_ parts: [Substring], _ feed: ParsedFeed) -> String {
        let number = Int(parts[1]) ?? 0
        guard number > 0, number <= feed.entries.count else { return "(no entry \(number))" }
        let entry = feed.entries[number - 1]
        switch parts[2] {
        case "content":
            if parts.count > 3, parts[3] == "prefix" {
                return escapeValue(String(entry.content.unicodeScalars.prefix(Self.pinnedPrefix)))
            }
            if parts.count > 3, parts[3] == "sha256" { return escapeValue(Hashes.sha256(entry.content)) }
            return escapeValue(entry.content)
        case "date": return escapeValue("\(entry.date.epochSeconds) \(entry.date.zoneOffsetSeconds)")
        case "tags": return escapeValue(entry.tags.joined(separator: "|"))
        case "enclosure":
            let index = Int(parts[3]) ?? 0
            guard index > 0, index <= entry.enclosures.count else {
                return "(no enclosure \(number).\(index))"
            }
            let enclosure = entry.enclosures[index - 1]
            switch parts[4] {
            case "url": return escapeValue(enclosure.url)
            case "mimeType": return escapeValue(enclosure.mimeType)
            default: return escapeValue(String(enclosure.size))
            }
        case "title": return escapeValue(entry.title)
        case "url": return escapeValue(entry.url)
        case "commentsURL": return escapeValue(entry.commentsURL)
        case "author": return escapeValue(entry.author)
        case "language": return escapeValue(entry.language)
        default: return escapeValue(entry.hash)
        }
    }

    /// The golden file writes one value per line, so the characters that would break a line are
    /// written as escapes, and an empty value is written as `(empty)`.
    private func escapeValue(_ value: String) -> String {
        guard !value.isEmpty else { return "(empty)" }
        var out = value.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\t", with: "\\t")
        return out
    }
}
