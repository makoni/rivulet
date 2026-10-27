// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`SanitizerOptions`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The options the sanitizer reads through.
///
/// The two embed values are the two the reference answers from `config.Opts`: the YouTube embed URL
/// override, whose domain is the allowlist entry a YouTube source is compared against, and the
/// Invidious instance. `Config` does not carry them yet, so they are passed in here.
struct SanitizerOptions: Sendable {
    /// The default embed URL prefix, the value `YOUTUBE_EMBED_URL_OVERRIDE` falls back to.
    static let defaultYouTubeEmbedURLPrefix = "https://www.youtube-nocookie.com/embed/"

    var openLinksInNewTab: Bool
    var youTubeEmbedURLPrefix: String
    var invidiousInstance: String

    init(
        openLinksInNewTab: Bool = false,
        youTubeEmbedURLPrefix: String = defaultYouTubeEmbedURLPrefix,
        invidiousInstance: String = ""
    ) {
        self.openLinksInNewTab = openLinksInNewTab
        self.youTubeEmbedURLPrefix = youTubeEmbedURLPrefix
        self.invidiousInstance = invidiousInstance
    }

    /// The domain the embed prefix resolves to, which is what `YouTubeEmbedDomain()` reports: the
    /// domain is read from the override, not assumed.
    var youTubeEmbedDomain: String { URLRules.domain(youTubeEmbedURLPrefix) }

    static let defaults = SanitizerOptions()
}
