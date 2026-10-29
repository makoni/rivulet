// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/media/media.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The media rules the format adapters read through: what one media element says about itself, the
/// way the merged group list is walked, and the way the attachments are collected. The order the
/// groups are walked in is the format's own — `RSSMedia` and `Atom10Adapter` differ there — while
/// these rules are the same for both.
enum MediaRules {
    /// One candidate attachment: the URL as the element carries it, the mime type the element's own
    /// rule gives, the size, whether a URL that cannot be resolved drops the candidate, and whether
    /// the deduplication compares the URL as the element carries it or the resolved one. The media
    /// elements drop an unresolvable URL, while the RSS `enclosure` keeps it as it was read.
    struct Candidate {
        var url: String
        var mimeType: String
        var size: Int
        var dropsWhenUnresolvable: Bool

        /// The map always holds the resolved value, so a candidate that is compared before it is
        /// resolved only matches a spelling that is already resolved: the two spellings of one file
        /// stay two attachments. The reference does that for the Atom media thumbnails and not for
        /// the RSS ones or for any other group, so the caller says which rule this candidate has.
        var comparedBeforeResolution: Bool = false
    }

    /// The candidates in the order the caller walked them, collected the way the reference collects
    /// them: the URL is trimmed, an empty URL is not an attachment at all, and the list is
    /// deduplicated by the value the candidate names — the resolved URL, or the URL as it was read
    /// when the reference checks the map before resolving.
    static func enclosures(siteURL: String, candidates: [Candidate]) -> [ParsedEnclosure] {
        var found: [ParsedEnclosure] = []
        var seen = Set<String>()

        for candidate in candidates {
            let url = UnicodeSpace.trim(candidate.url)
            guard !url.isEmpty else { continue }

            var resolved = url
            if let absolute = try? URLResolution.resolveToAbsolute(base: siteURL, relative: url) {
                resolved = absolute
            } else if candidate.dropsWhenUnresolvable {
                continue
            }

            let key = candidate.comparedBeforeResolution ? url : resolved
            if seen.contains(key) { continue }

            seen.insert(resolved)
            found.append(ParsedEnclosure(url: resolved, mimeType: candidate.mimeType, size: candidate.size))
        }

        return found
    }

    /// `Thumbnail`, which has no size and no type of its own. The key rule is the format's own, so
    /// the caller passes it.
    static func thumbnail(_ element: XMLElement, comparedBeforeResolution: Bool) -> Candidate {
        Candidate(url: attribute(element, local: "url"), mimeType: "image/*", size: 0,
            dropsWhenUnresolvable: true, comparedBeforeResolution: comparedBeforeResolution)
    }

    /// `Content`, whose type is its own attribute or the medium it declares.
    static func content(_ element: XMLElement) -> Candidate {
        Candidate(url: attribute(element, local: "url"), mimeType: contentMimeType(element),
            size: parsedSize(attribute(element, local: "fileSize")), dropsWhenUnresolvable: true)
    }

    /// `PeerLink`, which is read through `href` and falls back to the opaque type.
    static func peerLink(_ element: XMLElement) -> Candidate {
        let type = attribute(element, local: "type")
        return Candidate(url: attribute(element, local: "href"),
            mimeType: type.isEmpty ? "application/octet-stream" : type, size: 0,
            dropsWhenUnresolvable: true)
    }

    /// `FirstMediaDescription`: the first description that is not empty, reading the element's own
    /// descriptions before the groups'. The value is what the rule answers, with no trim, because
    /// `First()` returns the description as it was read.
    static func firstDescription(scope: XMLElement, groups: [XMLElement]) -> String {
        let descriptions = grouped(scope, groups, local: "description")
        for description in descriptions {
            let value = descriptionHTML(description)
            if !value.isEmpty { return value }
        }
        return ""
    }

    /// The elements of this name at the element's own level, in the media namespace.
    static func elements(_ scope: XMLElement, local: String) -> [XMLElement] {
        scope.children(local: local, namespace: FeedNamespaces.media)
    }

    /// The merged list `AllMedia...` builds: the element's own elements first, then each group's,
    /// in the order the groups are read.
    static func grouped(_ scope: XMLElement, _ groups: [XMLElement], local: String) -> [XMLElement] {
        elements(scope, local: local) + groups.flatMap { elements($0, local: local) }
    }

    // MARK: - The rules the three media types carry

    private static func contentMimeType(_ element: XMLElement) -> String {
        let type = attribute(element, local: "type")
        if !type.isEmpty { return type }

        switch attribute(element, local: "medium") {
        case "image": return "image/*"
        case "video": return "video/*"
        case "audio": return "audio/*"
        default: return "application/octet-stream"
        }
    }

    /// `Description.HTML()`: the type gate, then the link rule, then the newline. The reference
    /// compares the type with `==`, so this is not a fold.
    private static func descriptionHTML(_ element: XMLElement) -> String {
        let value = element.text
        guard attribute(element, local: "type") != "html" else { return value }
        let bytes = linkBytes([UInt8](value.utf8))
        return String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\n", with: "<br>")
    }

    /// `textLinkRegex`, which is `(?mi)(\bhttps?://[^\s]+)`, read on bytes: the fold, the ASCII
    /// word boundary, and the ASCII whitespace class Go's RE2 answers with, which is not the set
    /// Swift's `isWhitespace` answers with. The match is written back as it was read, so the case
    /// of the match survives.
    private static func linkBytes(_ bytes: [UInt8]) -> [UInt8] {
        func fold(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }
        func isWordByte(_ byte: UInt8) -> Bool {
            (fold(byte) >= UInt8(ascii: "a") && fold(byte) <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_")
        }
        func isSpaceByte(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: " ") || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
        }

        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let atBoundary = index == 0 || !isWordByte(bytes[index - 1])
            if atBoundary, let end = matchEnd(bytes, from: index, fold, isSpaceByte) {
                out += Array("<a href=\"".utf8)
                out += Array(bytes[index..<end])
                out += Array("\">".utf8)
                out += Array(bytes[index..<end])
                out += Array("</a>".utf8)
                index = end
                continue
            }

            out.append(bytes[index])
            index += 1
        }
        return out
    }

    /// Where `https?://` and the run of bytes that is not ASCII whitespace end, or `nil` when the
    /// position is not a match. The `s` is read when it is there, because the pattern prefers it.
    private static func matchEnd(_ bytes: [UInt8], from index: Int, _ fold: (UInt8) -> UInt8,
        _ isSpaceByte: (UInt8) -> Bool) -> Int? {
        var position = index
        for byte in [UInt8(ascii: "h"), UInt8(ascii: "t"), UInt8(ascii: "t"), UInt8(ascii: "p")] {
            guard position < bytes.count, fold(bytes[position]) == byte else { return nil }
            position += 1
        }
        if position < bytes.count, fold(bytes[position]) == UInt8(ascii: "s") { position += 1 }

        guard position + 2 < bytes.count, bytes[position] == UInt8(ascii: ":"),
            bytes[position + 1] == UInt8(ascii: "/"), bytes[position + 2] == UInt8(ascii: "/") else { return nil }
        position += 3

        let start = position
        while position < bytes.count, !isSpaceByte(bytes[position]) { position += 1 }
        return position > start ? position : nil
    }

    /// `strconv.ParseInt`, which answers zero for a value it cannot read.
    private static func parsedSize(_ value: String) -> Int { Int(value) ?? 0 }

    private static func attribute(_ element: XMLElement, local: String) -> String {
        element.attribute(local: local) ?? ""
    }
}
