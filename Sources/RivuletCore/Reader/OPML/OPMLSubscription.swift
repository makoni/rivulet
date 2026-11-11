// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/subscription.go (Apache-2.0); adapted for Swift/SQLite.

/// A feed the OPML read answers or the OPML write builds, the way the reference record carries it.
///
/// The reference record is the whole field set the format carries, and the import applies the
/// fields the port's schema has; the rest are read as data here but not persisted, which the suite
/// headers name. The `value` fields carry the attribute as the token read it, not the trimmed test
/// value, which is what the duplicate answer compares and what the create path writes.
struct OPMLSubscription: Equatable, Sendable {
    var title = ""
    var feedURL = ""
    var siteURL = ""
    var categoryName = ""
    var description = ""

    /// The miniflux settings, read by the name set the reference switches on. The names the format
    /// carries outside that set, such as `proxyUrl`, have no field here and are not read. The
    /// order below is the order the reference declares them in, which is the order the writer
    /// outputs them in.
    var scraperRules = ""
    var rewriteRules = ""
    var urlRewriteRules = ""
    var blocklistRules = ""
    var keeplistRules = ""
    var blockFilterEntryRules = ""
    var keepFilterEntryRules = ""
    var userAgent = ""
    var crawler = false
    var ignoreHTTPCache = false
    var fetchViaProxy = false
    var disabled = false
    var noMediaPlayer = false
    var hideGlobally = false
    var allowSelfSignedCertificates = false
    var disableHTTP2 = false
    var ignoreEntryUpdates = false
}
