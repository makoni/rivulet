// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/urllib (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The URL predicates the reader answers with. A value that does not parse is answered with as it
/// was read, which is what the reference does for `Domain`, `DomainWithoutWWW` and `RootURL`.
enum URLRules {
    /// Go reads `/\evil.com` as an ordinary path character, but a browser normalizes the backslash
    /// and reads it as an open redirect, so a value containing one is not a relative path here.
    static func isRelativePath(_ link: String) -> Bool {
        if link.isEmpty || link.contains("\\") { return false }
        guard let parsed = try? ParsedURL.parse(link) else { return false }
        return parsed.scheme.isEmpty && parsed.host.isEmpty
    }

    /// The prefix is checked on the value as it was read, before parsing, so a value that starts
    /// with whitespace is not absolute even though the reference would trim it when parsing.
    static func isAbsoluteURL(_ inputURL: String) -> Bool {
        guard inputURL.hasPrefix("https://") || inputURL.hasPrefix("http://") else { return false }
        guard let parsed = try? ParsedURL.parse(inputURL) else { return false }
        return parsed.isAbsolute
    }

    static func isHTTPS(_ websiteURL: String) -> Bool {
        guard let parsed = try? ParsedURL.parse(websiteURL) else { return false }
        return parsed.scheme.lowercased() == "https"
    }

    static func domain(_ websiteURL: String) -> String {
        guard let parsed = try? ParsedURL.parse(websiteURL) else { return websiteURL }
        return parsed.host
    }

    static func domainWithoutWWW(_ websiteURL: String) -> String {
        domain(websiteURL).replacingOccurrences(of: "www.", with: "", options: .anchored)
    }

    static func rootURL(_ websiteURL: String) -> String {
        if websiteURL.isEmpty { return "" }

        var value = websiteURL
        if value.hasPrefix("//") { value = "https://" + String(value.dropFirst(2)) }

        guard let parsed = try? ParsedURL.parse(value), !parsed.scheme.isEmpty, !parsed.host.isEmpty else {
            return websiteURL
        }
        return parsed.scheme + "://" + parsed.host + "/"
    }
}
