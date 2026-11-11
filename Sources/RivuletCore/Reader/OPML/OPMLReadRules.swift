// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/opml.go (Apache-2.0); adapted for Swift/SQLite. The
// value layer the reference decodes into (`UnmarshalXML`) has no port counterpart; the rules below
// are read as the reference reads them and applied over the tree the tolerant reader builds.

import Foundation

/// The rules the OPML read applies to the values it reads.
///
/// The subscription test is the url value alone, read against the whitespace class the reference's
/// `strings.TrimSpace` trims with. The title chain and the site-url fallback are the orders the
/// model's own methods define. The miniflux values are read by the set of names the reference's
/// switch carries, and only against the namespace a declaration resolves — an undefined prefix
/// stays as written, so the reference compares nothing and the record answers empty. The bool
/// values go through the set `strconv.ParseBool` accepts; the error names the attribute the rule
/// was reading, which is the reference's `opml: invalid miniflux attribute %q` shape, and the port
/// names the attribute rather than Go's wording.
enum OPMLReadRules {
    /// The namespace the reference compares the miniflux attribute names against.
    static let minifluxNamespace = "https://miniflux.app/opml"

    /// The test the format dispatches on: the url value trimmed against the whitespace class the
    /// reference's `strings.TrimSpace` trims with, which `UnicodeSpace` models and its own suite
    /// pins. Nothing else decides the branch: the `type` attribute is not in the model.
    static func isSubscription(feedURL: String) -> Bool {
        !UnicodeSpace.trim(feedURL).isEmpty
    }

    /// The chain the model reads a title through, in the order its method returns.
    static func title(title: String, text: String, siteURL: String, feedURL: String) -> String {
        if !title.isEmpty { return title }
        if !text.isEmpty { return text }
        if !siteURL.isEmpty { return siteURL }
        if !feedURL.isEmpty { return feedURL }
        return ""
    }

    /// The site url, which falls back to the feed url.
    static func siteURL(siteURL: String, feedURL: String) -> String {
        siteURL.isEmpty ? feedURL : siteURL
    }

    /// The set of names the reference's switch reads, the ones the format carries outside it — such
    /// as `proxyUrl` — have no field and answer nothing.
    static func isMinifluxName(_ name: String) -> Bool {
        minifluxNames.contains(name)
    }

    /// The half of that set the switch reads through the parse rule; the string names take the
    /// value as the attribute holds it, so `userAgent="true"` is the string.
    static func isBoolName(_ name: String) -> Bool {
        boolNames.contains(name)
    }

    /// The value `strconv.ParseBool` accepts, read as the set the function lists. A value outside
    /// it reaches as the error that names the attribute.
    static func boolValue(name: String, value: String) throws -> Bool {
        switch value {
        case "1", "t", "T", "true", "TRUE", "True": return true
        case "0", "f", "F", "false", "FALSE", "False": return false
        default: throw OPMLError.invalidMinifluxAttribute(name: name)
        }
    }

    private static let minifluxNames: Set<String> = [
        "scraperRules", "rewriteRules", "urlRewriteRules", "blocklistRules", "keeplistRules",
        "blockFilterEntryRules", "keepFilterEntryRules", "userAgent", "crawler",
        "ignoreHTTPCache", "fetchViaProxy", "disabled", "noMediaPlayer", "hideGlobally",
        "allowSelfSignedCertificates", "disableHTTP2", "ignoreEntryUpdates",
    ]

    private static let boolNames: Set<String> = [
        "crawler", "ignoreHTTPCache", "fetchViaProxy", "disabled", "noMediaPlayer", "hideGlobally",
        "allowSelfSignedCertificates", "disableHTTP2", "ignoreEntryUpdates",
    ]
}
