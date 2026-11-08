// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0 Ported from Miniflux internal/reader/subscription/finder.go
// (`FindSubscriptions`) (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The order is the reference's for the two steps this port has. The response is read before the
/// body, so a status failure is reported before anything is scanned; the format is decided from the
/// bytes before any token is read, and for a document that is already a feed the answer is the URL
/// the response came from, which is the reference's `EffectiveURL()` and not the URL the call was
/// given — the two are different answers for a document that was redirected. Only after that does
/// the scan read the document, and the base it resolves against is the URL this call was given,
/// which is what the reference answers when the document carries no `<base href>`: its own read of
/// that tag is not ported, and its canonical step does not change the base the scan is given. What
/// the reference has and this port does not — the `<base href>` read, the canonical URL, the
/// YouTube, GitHub and RSS-Bridge handlers, the well-known paths, are recorded in `docs/parity.md`,
/// as is the fact that the reference's subscription value also carries a title and a format that
public struct SubscriptionFinder: Sendable {
    private let fetcher: Fetcher
    private let builder: FetchRequestBuilder

    /// Creates the finder around the fetcher and the options the request is built from.
    public init(fetcher: Fetcher, options: FetcherOptions) {
        self.fetcher = fetcher
        self.builder = FetchRequestBuilder(options: options)
    }

    /// The feed urls the document offers, in the order the tokens arrive.
    ///
    /// - Parameter websiteURL: The url the request was for, which is also the base the scan
    ///   resolves against.
    /// - Throws: the failure the response reports, which is what the reference hands its caller
    ///   and what the handler answers 500 for.
    public func findFeedURLs(from websiteURL: String) async throws -> [String] {
        let response = try await fetcher.fetch(builder.build(url: websiteURL,
            userAgent: builder.options.userAgent))
        if let error = response.error() { throw error }

        let detected = FeedFormatDetector.detect(response.body)
        if detected.format != .unknown { return [response.effectiveURL.absoluteString] }

        return SubscriptionDocumentLinks.feedURLs(document: response.body,
            contentType: response.contentType, documentURL: websiteURL)
    }
}
