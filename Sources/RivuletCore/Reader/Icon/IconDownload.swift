// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`downloadIcon`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// Reads a fetch response as the icon it is.
///
/// The reference reads the error before the body, so a status failure is reported even when the
/// body is empty, and `ReadBody` reports an empty body for any response — including the
/// conditional hit the feed path accepts, because there the empty body means there is nothing
/// to re-parse. The size cap belongs to the fetcher: by the time a response reaches this layer
/// the bytes it carries are the bytes that were read.
enum IconDownload {
    static func candidate(from response: FetchResponse) throws -> IconCandidate {
        if let error = response.error() { throw error }

        // The icon path has no conditional-hit exception, so this is the rule the
        // reference's `ReadBody` states, read again rather than inherited from the feed
        // response's.
        guard !response.body.isEmpty else { throw FetchError.emptyBody }

        return IconCandidate(mimeType: response.contentType, content: response.body)
    }
}
