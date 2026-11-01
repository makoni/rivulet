// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/urllib (`JoinBaseURLAndPath`) and Go's standard library `net/url`
// (`url.JoinPath`) with `path.Join` (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Joining a base URL with a path element, which is what the reference does for the default icon.
///
/// The join reads the escaped path, because Go joins `EscapedPath()` with the elements and the
/// elements are expected to be already escaped: a base path read as `a%2fb` keeps its escape
/// instead of becoming two elements, and the join escapes nothing itself. The cleaning is Go's
/// `path.Join`: empty elements are ignored, multiple slashes are reduced to one, a `.` element
/// is dropped, an inner `..` removes the element before it, and a `..` that begins a rooted
/// path has nothing to remove, so the root stays. The trailing slash is put back when the last
/// element had one, which is the only case that keeps a slash here, because the cleaning
/// removes it. The base's query is not part of the join and stays after the path.
enum URLJoinPath {
    /// Joins `baseURL` and `path` the way `JoinBaseURLAndPath` does.
    ///
    /// - Throws: ``URLJoinError/emptyBaseURL(_:)`` and ``URLJoinError/emptyPath(_:)`` for
    /// the two guards the   reference runs before it joins,
    /// ``URLJoinError/invalidBase(_:)`` when the base cannot be parsed, and   the URL
    /// layer's error when an element carries an invalid escape, which is what Go's
    /// `setPath`   reports.
    static func join(baseURL: String, path: String) throws -> String {
        guard !baseURL.isEmpty else { throw URLJoinError.emptyBaseURL }
        guard !path.isEmpty else { throw URLJoinError.emptyPath }

        var url: ParsedURL
        do {
            url = try ParsedURL.parse(baseURL)
        } catch let error as URLParseError {
            throw URLJoinError.invalidBase(error)
        }
        let elements = [url.escapedPath, path]

        var joined: String
        if elements[0].hasPrefix("/") {
            joined = joinElements(elements)
        } else {
            // Go roots a relative base for the cleaning and then drops the root
            // again, so a relative base keeps its form but cannot carry a `..` above
            // itself.
            joined = String(joinElements(["/" + elements[0], path]).dropFirst())
        }

        if elements[1].hasSuffix("/") && !joined.hasSuffix("/") { joined += "/" }

        let decoded = try URLEscaping.unescape(joined, mode: .path)
        url.path = decoded
        // Go records the joined form as the raw path only when re-encoding the decoded
        // value does not give that form back, which is what keeps `a%2fb` written as it
        // was read.
        url.rawPath = URLEscaping.escape(decoded, mode: .path) == joined ? "" : joined
        return url.description
    }

    /// Go's `path.Join` for the elements this reference joins: empty elements are ignored
    /// and the result is cleaned.
    private static func joinElements(_ elements: [String]) -> String {
        let parts = elements.filter { !$0.isEmpty }
        return parts.isEmpty ? "" : clean(parts.joined(separator: "/"))
    }

    /// Go's `path.Clean`, the lexical rules the join runs through.
    private static func clean(_ path: String) -> String {
        if path.isEmpty { return "." }

        let rooted = path.hasPrefix("/")
        var out: [String] = []
        var protected = 0

        for element in path.split(separator: "/", omittingEmptySubsequences: true) {
            if element == "." { continue }

            if element == ".." {
                if out.count > protected {
                    out.removeLast()
                } else if !rooted {
                    out.append("..")
                    protected = out.count
                }
                continue
            }

            out.append(String(element))
        }

        if out.isEmpty { return rooted ? "/" : "." }
        return (rooted ? "/" : "") + out.joined(separator: "/")
    }
}
