// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The allowlists the sanitizer answers against, transcribed from the reference.
///
/// The tag map is the reference's, with the attributes each tag keeps; a tag that is not in it is
/// not written, but its content still is. The iframe domains, the blocked resource substrings and
/// the data attribute prefixes are checked on the value as it was read, before it is resolved.
enum SanitizerAllowlists {
    static func attributes(for tag: String) -> [String] {
        allowedHTMLTagsAndAttributes[tag] ?? []
    }

    static func isAllowedTag(_ tag: String) -> Bool {
        allowedHTMLTagsAndAttributes[tag] != nil
    }

    static func isAllowedIFrameDomain(_ domain: String, options: SanitizerOptions) -> Bool {
        if iframeAllowList.contains(domain) { return true }

        let embedDomain = options.youTubeEmbedDomain
        if !embedDomain.isEmpty && domain == trimmingWWW(embedDomain) { return true }

        if !options.invidiousInstance.isEmpty && domain == trimmingWWW(options.invidiousInstance) { return true }
        return false
    }

    static func isBlockedResource(_ absoluteURL: String) -> Bool {
        blockedResourceURLSubstrings.contains { absoluteURL.contains($0) }
    }

    static func isValidDataAttribute(_ value: String) -> Bool {
        dataAttributeAllowedPrefixes.contains { value.hasPrefix($0) }
    }

    private static func trimmingWWW(_ value: String) -> String {
        value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }

    private static let allowedHTMLTagsAndAttributes: [String: [String]] = [
        "a": ["href", "title", "id"],
        "abbr": ["title"],
        "acronym": ["title"],
        "aside": [],
        "audio": ["src"],
        "blockquote": [],
        "b": [],
        "br": [],
        "caption": [],
        "cite": [],
        "code": [],
        "dd": ["id"],
        "del": [],
        "dfn": [],
        "dl": ["id"],
        "dt": ["id"],
        "em": [],
        "figcaption": [],
        "figure": [],
        "h1": ["id"],
        "h2": ["id"],
        "h3": ["id"],
        "h4": ["id"],
        "h5": ["id"],
        "h6": ["id"],
        "hr": [],
        "i": [],
        "iframe": ["width", "height", "frameborder", "src", "allowfullscreen"],
        "img": ["alt", "title", "src", "srcset", "sizes", "width", "height", "fetchpriority", "decoding"],
        "ins": [],
        "kbd": [],
        "li": ["id"],
        "ol": ["id"],
        "p": [],
        "picture": [],
        "pre": [],
        "q": ["cite"],
        "rp": [],
        "rt": [],
        "rtc": [],
        "ruby": [],
        "s": [],
        "small": [],
        "samp": [],
        "source": ["src", "type", "srcset", "sizes", "media"],
        "strong": [],
        "sub": [],
        "sup": ["id"],
        "table": [],
        "td": ["rowspan", "colspan"],
        "tfoot": [],
        "th": ["rowspan", "colspan"],
        "thead": [],
        "time": ["datetime"],
        "tr": [],
        "u": [],
        "ul": ["id"],
        "var": [],
        "video": ["poster", "height", "width", "src"],
        "wbr": [],

        // MathML, as the reference's list has it.
        "annotation": [],
        "annotation-xml": [],
        "maction": [],
        "math": ["xmlns"],
        "merror": [],
        "mfrac": [],
        "mi": [],
        "mmultiscripts": [],
        "mn": [],
        "mo": [],
        "mover": [],
        "mpadded": [],
        "mphantom": [],
        "mprescripts": [],
        "mroot": [],
        "mrow": [],
        "ms": [],
        "mspace": [],
        "msqrt": [],
        "mstyle": [],
        "msub": [],
        "msubsup": [],
        "msup": [],
        "mtable": [],
        "mtd": [],
        "mtext": [],
        "mtr": [],
        "munder": [],
        "munderover": [],
        "semantics": [],
    ]

    private static let iframeAllowList: Set<String> = [
        "bandcamp.com", "cdn.embedly.com", "dailymotion.com", "framatube.org", "open.spotify.com",
        "player.bilibili.com", "player.twitch.tv", "player.vimeo.com", "soundcloud.com", "vk.com",
        "w.soundcloud.com", "youtube-nocookie.com", "youtube.com",
    ]

    private static let blockedResourceURLSubstrings: [String] = [
        "api.flattr.com",
        "www.facebook.com/sharer.php",
        "feeds.feedburner.com",
        "feedsportal.com",
        "linkedin.com/shareArticle",
        "pinterest.com/pin/create/button/",
        "stats.wordpress.com",
        "twitter.com/intent/tweet",
        "twitter.com/share",
        "x.com/intent/tweet",
        "x.com/share",
    ]

    private static let dataAttributeAllowedPrefixes: [String] = [
        "data:image/avif",
        "data:image/apng",
        "data:image/png",
        "data:image/svg",
        "data:image/svg+xml",
        "data:image/jpg",
        "data:image/jpeg",
        "data:image/gif",
        "data:image/webp",
    ]
}
