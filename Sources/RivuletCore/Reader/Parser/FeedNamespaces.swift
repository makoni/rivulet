// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader (the namespaces its field tags name); adapted for Swift/SQLite.

/// The namespaces the format adapters match element names against, the ones the reference's field tags
/// name. A tag with no namespace matches any namespace, which is what the tree's own match does.
enum FeedNamespaces {
    /// The `DefaultSpace` the reference gives the decoder for RSS. It is not a URL: it is what
    /// `translate` substitutes for a name with no prefix when the document declares no default
    /// namespace.
    static let rssDefault = "rss"

    /// The RSS 1.0 namespace. Only one field tag in the reference names it explicitly — the RDF item
    /// title — while the channel title tag names none, so the two resolve differently.
    static let rss10 = "http://purl.org/rss/1.0/"

    static let atom = "http://www.w3.org/2005/Atom"
    static let dublinCore = "http://purl.org/dc/elements/1.1/"
    static let contentModule = "http://purl.org/rss/1.0/modules/content/"
    static let media = "http://search.yahoo.com/mrss/"
    static let itunes = "http://www.itunes.com/dtds/podcast-1.0.dtd"
    static let googlePlay = "http://www.google.com/schemas/play-podcasts/1.0"
    static let feedBurner = "http://rssnamespace.org/feedburner/ext/1.0"
}
