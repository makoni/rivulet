// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`findIcon`, `downloadIcon`,
// `fetchIconsFromHTMLDocument`, `fetchDefaultIcon`) (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The icon search for one feed.
///
/// The order is the reference's: the feed's own icon URL, then the website document, then the root
/// document when the website URL has a path, then the default icon joined to the root URL. The
/// first step that produces an icon answers, and a step that fails is skipped — the reference logs
/// it and continues — except the default icon, whose failure is the answer the search returns. A
/// step that answers nothing is skipped too, which is what the reference's `else if icon != nil`
/// reads: the download half answers nothing for an image the resize rejects, so the search goes on,
/// and the search itself can answer nothing. A `data:` href answers with the value the encoding
/// branch produced, without a request and without the resize, because the reference's
/// `parseImageDataURL` does not call it, and a failing download inside a document moves on to the
/// next href.
///
/// What this file does not own: the four selector branches, the `data:` shape, the charset layer,
/// the URL resolution, the join cleaning and the request headers are the rules of those layers and
/// are pinned by their own suites; the reference logs each step, which this port has no layer for.
/// The empty-body rule is the response layer's, read by both paths here, and what
/// `IconDownloadTests` pins is the icon path having no conditional-hit exception; the basis that
/// rule measures is recorded in `docs/parity.md`. The resize is the rule `IconResize` states, read
/// here as the call `downloadIcon` makes after the checksum. The proxy decision for an icon belongs
/// to the feed row and to the caller that wires the search to a feed, so no request here carries
/// one, and the user agent a request carries is the value that caller hands this type.
struct IconFinder {
    private let fetcher: Fetcher
    private let builder: FetchRequestBuilder
    private let websiteURL: String
    private let feedIconURL: String
    private let userAgent: String

    init(fetcher: Fetcher, options: FetcherOptions, websiteURL: String, feedIconURL: String = "",
         userAgent: String = "") {
        self.fetcher = fetcher
        self.builder = FetchRequestBuilder(options: options)
        self.websiteURL = websiteURL
        self.feedIconURL = feedIconURL
        self.userAgent = userAgent
    }

    /// Runs the search.
    ///
    /// - Throws: the failure of the last step, which is what `findIcon` returns. The earlier steps'
    /// failures are skipped. - Returns: the first step that produced an icon, or nothing when no
    /// step did.
    func find() async throws -> IconCandidate? {
        if !feedIconURL.isEmpty {
            do {
                if let icon = try await download(feedIconURL) { return icon }
            } catch {
                // A failing step is logged upstream and the search goes on; there is no layer here.
            }
        }

        var documentURLs = [websiteURL]
        let rootURL = URLRules.rootURL(websiteURL)
        if rootURL != websiteURL { documentURLs.append(rootURL) }

        for documentURL in documentURLs {
            do {
                if let icon = try await iconsFromDocument(documentURL) { return icon }
            } catch {
                // A failing step is logged upstream and the search goes on; there is no layer here.
            }
        }

        return try await download(URLJoinPath.join(baseURL: rootURL, path: "favicon.ico"))
    }

    /// The download half: the response read as the reference reads it, then the resize the
    /// reference runs on what the read produced. An image the resize rejects answers nothing, which
    /// is what the reference continues past.
    private func download(_ iconURL: String) async throws -> IconCandidate? {
        let candidate = try IconDownload.candidate(from:
            try await fetcher.fetch(builder.build(url: iconURL, userAgent: userAgent)))
        return IconResize.resize(candidate)
    }

    /// The document step: the hrefs the scan offers, answered in the order they arrive. A value the
    /// parse cannot read is skipped, which is what the scan already does, and so is a download that
    /// answers nothing or fails.
    private func iconsFromDocument(_ documentURL: String) async throws -> IconCandidate? {
        let documentRequest = try await builder.build(url: documentURL, userAgent: userAgent)
        let response = try await fetcher.fetch(documentRequest)
        if let error = response.error() { throw error }

        let hrefs = IconDocumentLinks.iconURLs(document: response.body,
            contentType: response.contentType, documentURL: documentURL)
        for href in hrefs {
            if href.hasPrefix("data:") { return try IconDataURL.parse(href) }
            do {
                if let icon = try await download(href) { return icon }
            } catch {
                continue
            }
        }

        return nil
    }
}
