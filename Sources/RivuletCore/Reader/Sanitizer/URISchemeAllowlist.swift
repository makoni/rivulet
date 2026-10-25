// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer/url.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The allowlist for URLs in sanitized feed body content, transcribed from the reference. It is
/// intentionally broad; the stricter surfaces use `URLRules.isAbsoluteURL` or
/// `URLRules.isRelativePath`, as the reference does.
///
/// The scheme is the part before the first colon, compared case-insensitively per RFC 3986 §3.1.
enum URISchemeAllowlist {
    private static let validURISchemes: [String] = [
        // Most common schemes on top.
        "https",
        "http",

        // Then the rest, in the reference's order.
        "apt",
        "bitcoin",
        "callto",
        "dav",
        "davs",
        "ed2k",
        "facetime",
        "feed",
        "ftp",
        "geo",
        "git",
        "gopher",
        "irc",
        "irc6",
        "ircs",
        "itms-apps",
        "itms",
        "magnet",
        "mailto",
        "news",
        "nntp",
        "rtmp",
        "sftp",
        "sip",
        "sips",
        "shortcuts",
        "skype",
        "spotify",
        "ssh",
        "steam",
        "svn",
        "svn+ssh",
        "tel",
        "webcal",
        "xmpp",

        // iOS Apps.
        "opener",
        "hack",
    ]

    static func hasValidScheme(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":") else { return false }
        let scheme = String(value[..<colon])
        if scheme.isEmpty { return false }
        return validURISchemes.contains { $0.caseInsensitiveCompare(scheme) == .orderedSame }
    }
}
