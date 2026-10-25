// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`Parse`, `parse`, `getScheme`, `parseAuthority`,
// `parseHost`, `validOptionalPort`, `setPath`, `setFragment`), the parts the reader uses; adapted
// for Swift/SQLite.

import Foundation

extension ParsedURL {
    /// Parse, in Go's order: the fragment is cut first, then the scheme, then the query, then the
    /// opaque form or the optional authority, then the path.
    static func parse(_ rawURL: String) throws -> ParsedURL {
        var url = ParsedURL()
        var rest = rawURL

        if let hash = rest.firstIndex(of: "#") {
            let fragmentPart = String(rest[rest.index(after: hash)...])
            rest = String(rest[..<hash])
            if !fragmentPart.isEmpty { try url.setFragment(fragmentPart) }
        }

        try checkControlCharacters(rest)
        rest = try readScheme(rest, &url)
        rest = readQueryPart(rest, &url)
        rest = try readAuthorityOrOpaque(rest, &url)

        if rest.isEmpty { return url }
        try url.setPath(rest)
        return url
    }

    /// Go's `getScheme`: an invalid character before the colon means there is no scheme, and only a
    /// colon at the start of the value is an error.
    private static func readScheme(_ rest: String, _ url: inout ParsedURL) throws -> String {
        guard let colon = rest.firstIndex(of: ":") else { return rest }

        let candidate = String(rest[..<colon])
        if candidate.isEmpty { throw URLParseError.missingScheme }
        if !isScheme(candidate) { return rest }

        url.scheme = candidate.lowercased()
        return String(rest[rest.index(after: colon)...])
    }

    /// The query is kept as it was read; only `query()` decodes it. A value ending with a single
    /// `?` keeps it, which is Go's `ForceQuery`.
    private static func readQueryPart(_ rest: String, _ url: inout ParsedURL) -> String {
        guard let question = rest.firstIndex(of: "?") else { return rest }

        if question == rest.index(before: rest.endIndex) && !rest[..<question].contains("?") {
            url.forceQuery = true
            return String(rest[..<question])
        }
        url.rawQuery = String(rest[rest.index(after: question)...])
        return String(rest[..<question])
    }

    /// The opaque form, the optional authority, or the flag saying there is no authority. A
    /// relative reference cannot start its first segment with a colon.
    private static func readAuthorityOrOpaque(_ rest: String, _ url: inout ParsedURL) throws -> String {
        if !rest.hasPrefix("/") {
            if !url.scheme.isEmpty {
                url.opaqueRaw = rest
                return ""
            }
            let segment = String(rest.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
            if segment.contains(":") { throw URLParseError.colonInFirstSegment(segment) }
            return rest
        }

        if !rest.hasPrefix("//") {
            if !url.scheme.isEmpty { url.omitHost = true }
            return rest
        }

        let authorityPart = String(rest.dropFirst(2))
        guard let slash = authorityPart.firstIndex(of: "/") else {
            try parseAuthority(authorityPart, &url)
            return ""
        }
        try parseAuthority(String(authorityPart[..<slash]), &url)
        // The slash that ends the authority belongs to the path, as it does in Go.
        return String(authorityPart[slash...])
    }

    /// Go's `getScheme` character class.
    private static func isScheme(_ candidate: String) -> Bool {
        var first = true
        for byte in candidate.utf8 {
            if isLetter(byte) { first = false; continue }
            if isDigit(byte) || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: ".") {
                if first { return false }
                continue
            }
            return false
        }
        return true
    }

    /// Go's `parseAuthority`: the user is read before the host, and the host is validated.
    private static func parseAuthority(_ authority: String, _ url: inout ParsedURL) throws {
        if let at = authority.lastIndex(of: "@") {
            url.userInfo = String(authority[..<at])
            let hostPart = String(authority[authority.index(after: at)...])
            if !hostPart.isEmpty { url.host = try parseHost(hostPart) }
            return
        }
        url.host = try parseHost(authority)
    }

    /// Go's `parseHost`: a bracket must not open inside the host, a bracketed host must be closed,
    /// a port must be a valid optional port, and a character outside the host class is the error.
    private static func parseHost(_ hostport: String) throws -> String {
        if let open = hostport.lastIndex(of: "[") {
            if hostport.distance(from: hostport.startIndex, to: open) > 0 {
                throw URLParseError.invalidHost(character: "[")
            }
            guard let closing = hostport.lastIndex(of: "]") else {
                throw URLParseError.unclosedBracketHost
            }
            let portPart = String(hostport[hostport.index(after: closing)...])
            if !isValidOptionalPort(portPart) { throw URLParseError.invalidPort(portPart) }
            return hostport
        }

        if let colon = hostport.lastIndex(of: ":") {
            let portPart = String(hostport[hostport.index(after: colon)...])
            if !portPart.isEmpty && !portPart.utf8.allSatisfy(isDigit) {
                throw URLParseError.invalidPort(":" + portPart)
            }
            try checkHostCharacters(String(hostport[..<colon]))
            return hostport
        }

        try checkHostCharacters(hostport)
        return hostport
    }

    private static func isValidOptionalPort(_ portPart: String) -> Bool {
        if portPart.isEmpty { return true }
        if portPart.first != ":" { return false }
        return portPart.utf8.dropFirst().allSatisfy(isDigit)
    }

    private static func checkHostCharacters(_ host: String) throws {
        for byte in host.utf8 where URLEscaping.shouldEscape(byte, mode: .host) {
            throw URLParseError.invalidHost(character: Character(Unicode.Scalar(byte)))
        }
    }

    /// Go's `stringContainsCTLByte`: a byte below the space or the DEL character.
    private static func checkControlCharacters(_ value: String) throws {
        for byte in value.utf8 {
            if byte < UInt8(ascii: " ") || byte == 0x7f {
                throw URLParseError.controlCharacter(Character(Unicode.Scalar(byte)))
            }
        }
    }

    /// Go's `setFragment`, which follows the same rule as `setPath`: the read form is recorded only
    /// when it is not already the canonical encoding of the decoded value.
    private mutating func setFragment(_ read: String) throws {
        fragment = try URLEscaping.unescape(read, mode: .fragment)
        rawFragment = URLEscaping.escape(fragment, mode: .fragment) == read ? "" : read
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
