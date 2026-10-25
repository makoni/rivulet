// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`url.URL`), the subset the reader resolves through;
// adapted for Swift/SQLite.

import Foundation

/// A parsed URL as Go's `url.URL` holds it, for the parts the reader uses.
///
/// `path` and `fragment` are decoded; `rawPath`, `rawFragment` and `rawQuery` are the forms the
/// value was read as, recorded only when re-encoding the decoded value does not produce that form
/// again — which is what keeps `http://golang.org/a%2Fb` readable as it was written. A scheme with
/// no authority keeps its rest as it was read, which is why `mailto:` values are not resolved
/// against the feed URL.
///
/// The fields Go has but this subset does not — the zone identifier of a bracketed host, the `*`
/// path, the username/password split of the authority, and the count limit `ParseQuery` enforces —
/// are the subset boundary recorded in `docs/parity.md`.
struct ParsedURL: Equatable, Sendable {
    var scheme: String = ""
    var opaqueRaw: String = ""
    var userInfo: String = ""
    var host: String = ""
    var path: String = ""
    var rawPath: String = ""
    var rawQuery: String = ""
    var fragment: String = ""
    var rawFragment: String = ""

    /// Go's `ForceQuery`: the value ends with a single `?`, so the rebuilt string keeps it.
    var forceQuery: Bool = false

    /// Go's `OmitHost`: the scheme is followed by a path with no authority, so the rebuilt string
    /// does not write the `//` back.
    var omitHost: Bool = false

    var isOpaquePath: Bool { !opaqueRaw.isEmpty }

    /// Go's `IsAbs`: the value is absolute when it carries a scheme.
    var isAbsolute: Bool { !scheme.isEmpty }

    /// Go's `Hostname`, which reports a bracketed host without its brackets.
    var hostName: String {
        let hostPart = Self.splitHostAndPort(host).host
        if hostPart.hasPrefix("[") && hostPart.hasSuffix("]") {
            return String(hostPart.dropFirst().dropLast())
        }
        return hostPart
    }

    /// Go's `EscapedPath`: the recorded raw form when it is a valid encoding of the decoded path,
    /// otherwise the re-encoded path.
    var escapedPath: String {
        if !rawPath.isEmpty, URLEscaping.isValidEncoded(rawPath, mode: .path),
            (try? URLEscaping.unescape(rawPath, mode: .path)) == path {
            return rawPath
        }
        return URLEscaping.escape(path, mode: .path)
    }

    /// Go's `EscapedFragment`.
    var escapedFragment: String {
        if !rawFragment.isEmpty, URLEscaping.isValidEncoded(rawFragment, mode: .fragment),
            (try? URLEscaping.unescape(rawFragment, mode: .fragment)) == fragment {
            return rawFragment
        }
        return URLEscaping.escape(fragment, mode: .fragment)
    }

    /// Go's `String()`.
    var description: String {
        var result = ""
        if !scheme.isEmpty { result += scheme + ":" }

        if isOpaquePath {
            result += opaqueRaw
        } else {
            if !scheme.isEmpty || !host.isEmpty || !userInfo.isEmpty {
                if omitHost && host.isEmpty && userInfo.isEmpty {
                    // Go omits an empty authority it was told to omit.
                } else {
                    if !host.isEmpty || !path.isEmpty || !userInfo.isEmpty { result += "//" }
                    if !userInfo.isEmpty { result += userInfo + "@" }
                    result += host
                }
            }

            let encodedPath = escapedPath
            if !encodedPath.isEmpty && !encodedPath.hasPrefix("/") && !host.isEmpty { result += "/" }
            result += encodedPath
        }

        if forceQuery || !rawQuery.isEmpty { result += "?" + rawQuery }
        if !fragment.isEmpty { result += "#" + escapedFragment }
        return result
    }

    /// Go's `Query()`.
    func query() -> QueryValues { QueryValues.parse(rawQuery) }

    /// Go's `ResolveReference`, in Go's order: the scheme is taken from the base only when the
    /// reference does not carry its own, a reference that carries an authority is cleaned before it
    /// is returned, and a reference with no path takes the base query and fragment.
    func resolving(reference: ParsedURL) -> ParsedURL {
        var resolved = reference
        if reference.scheme.isEmpty { resolved.scheme = scheme }

        if !reference.scheme.isEmpty || !reference.host.isEmpty || !reference.userInfo.isEmpty {
            // Go ignores the error here because the reference carries a validly-escaped path.
            try? resolved.setPath(Self.resolvePath(base: reference.escapedPath, reference: ""))
            return resolved
        }

        if reference.isOpaquePath {
            resolved.userInfo = ""
            resolved.host = ""
            resolved.path = ""
            return resolved
        }

        if reference.path.isEmpty && !reference.forceQuery && reference.rawQuery.isEmpty {
            resolved.rawQuery = rawQuery
            if reference.fragment.isEmpty {
                resolved.fragment = fragment
                resolved.rawFragment = rawFragment
            }
        }

        if reference.path.isEmpty && isOpaquePath {
            resolved.opaqueRaw = opaqueRaw
            resolved.userInfo = ""
            resolved.host = ""
            return resolved
        }

        resolved.host = host
        resolved.userInfo = userInfo
        try? resolved.setPath(Self.resolvePath(base: escapedPath, reference: reference.escapedPath))
        return resolved
    }

    /// Go's `setPath`: the read form is recorded as `rawPath` only when it is not already the
    /// canonical encoding of the decoded path.
    mutating func setPath(_ read: String) throws {
        path = try URLEscaping.unescape(read, mode: .path)
        rawPath = URLEscaping.escape(path, mode: .path) == read ? "" : read
    }

    /// Go's `splitHostPort`, which reports the whole host when the port is not a valid optional
    /// port.
    private static func splitHostAndPort(_ hostport: String) -> (host: String, port: String) {
        let bytes = Array(hostport.utf8)
        guard let colon = bytes.lastIndex(of: UInt8(ascii: ":")) else { return (hostport, "") }

        var hostPart = String(decoding: bytes[0..<colon], as: UTF8.self)
        let port = String(decoding: bytes[(colon + 1)...], as: UTF8.self)
        if !port.isEmpty && !port.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) {
            return (hostport, "")
        }

        if hostPart.hasPrefix("[") && hostPart.hasSuffix("]") {
            hostPart = String(hostPart.dropFirst().dropLast())
        }
        return (hostPart, port)
    }
}
