// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/checker.go (`UpdateOrCreateFeedIcon` and
// `CreateFeedIconIfMissing`) (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Runs the icon search for one stored feed and lets the storage layer decide what to keep.
///
/// The reference logs each failure and continues; this port has no logging layer, so a failure ends
/// inside the checker: nothing is written and nothing reaches the caller. What the checker owns
/// is the guard and the two storage decisions — the store, which the repository deduplicates by
/// hash, and the link. The request builder half upstream carries — cookie, timeout, proxy, TLS
/// errors and HTTP2 — is documented as deferred in `docs/reference-notes.md`; what is read here
/// is the feed's user agent, which upstream hands to the builder and which this port passes on
/// as the same value.
struct IconChecker {
    private let finder: IconFinder
    private let icons: IconRepository
    private let feedID: Int

    init(fetcher: Fetcher, options: FetcherOptions, icons: IconRepository, feedID: Int,
         websiteURL: String, feedIconURL: String = "", userAgent: String = "") {
        self.finder = IconFinder(fetcher: fetcher, options: options, websiteURL: websiteURL,
            feedIconURL: feedIconURL, userAgent: userAgent)
        self.icons = icons
        self.feedID = feedID
    }

    /// The path upstream runs for a forced refresh: no guard, so a feed that already has an icon is
    /// pointed at whatever the search answers with.
    func updateOrCreate() async {
        let candidate: IconCandidate?
        do {
            candidate = try await finder.find()
        } catch {
            return
        }

        // The branch `else if icon == nil` reads: the search answered without a failure, which the
        // resize can do for an image it rejects, and nothing is written for it.
        guard let candidate else { return }
        await store(candidate)
    }

    /// The path upstream runs when the feed is not being forced: the guard, which reads the mapping
    /// for this feed rather than the icon table, so a feed with no mapping of its own still
    /// runs the search. A guard read that itself fails answers as "no icon", which is what
    /// upstream's `HasFeedIcon` does when the scan reports nothing.
    func createIfMissing() async {
        let hasIcon = try? await icons.hasIcon(feedID: feedID)
        if hasIcon == true { return }
        await updateOrCreate()
    }

    /// The two decisions `StoreFeedIcon` makes: the row, which the repository writes only when the
    /// hash is not stored yet, and the mapping, which it writes on either branch.
    private func store(_ candidate: IconCandidate) async {
        guard let icon = try? await icons.insert(hash: candidate.hash,
            mimeType: candidate.mimeType, content: candidate.content),
            let iconID = icon.id else { return }

        try? await icons.link(feedID: feedID, iconID: iconID)
    }
}
