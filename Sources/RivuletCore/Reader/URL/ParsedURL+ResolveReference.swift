// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`resolvePath`), the part the reader uses; adapted
// for Swift/SQLite.

import Foundation

extension ParsedURL {
    /// Go's `resolvePath`, which cleans as it joins: an absolute reference replaces the path, a
    /// relative one replaces the last segment of the base path, dot segments are removed, a `..`
    /// drops the segment before it, and a value that ended with a dot segment keeps its trailing
    /// slash.
    static func resolvePath(base: String, reference: String) -> String {
        let full = join(base: base, reference: reference)
        if full.isEmpty { return "" }

        var cleaned = "/"
        var remaining = full
        var first = true
        var found = true
        var segment = ""

        while found {
            if let slash = remaining.firstIndex(of: "/") {
                segment = String(remaining[..<slash])
                remaining = String(remaining[remaining.index(after: slash)...])
            } else {
                segment = remaining
                remaining = ""
                found = false
            }

            switch segment {
            case ".": first = false
            case "..":
                cleaned = popSegment(cleaned)
                first = cleaned == "/"
            default:
                if !first { cleaned += "/" }
                cleaned += segment
                first = false
            }
        }

        if segment == "." || segment == ".." { cleaned += "/" }
        if cleaned.count > 1 && cleaned.dropFirst().first == "/" { return String(cleaned.dropFirst()) }
        return cleaned
    }

    /// Go's `resolvePath` opening: a reference that starts with the path separator takes the whole
    /// path, otherwise it replaces the last segment of the base path.
    private static func join(base: String, reference: String) -> String {
        if reference.isEmpty { return base }
        if reference.hasPrefix("/") { return reference }
        guard let lastSlash = base.lastIndex(of: "/") else { return reference }
        return String(base[...lastSlash]) + reference
    }

    /// A `..` pops the whole segment before it, not just the characters of that segment.
    private static func popSegment(_ cleaned: String) -> String {
        let body = String(cleaned.dropFirst())
        guard let previous = body.lastIndex(of: "/") else { return "/" }
        return "/" + String(body[body.startIndex..<previous])
    }
}
