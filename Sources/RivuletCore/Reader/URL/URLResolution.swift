// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/urllib (`resolveToAbsoluteURL`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// Relative URL resolution against a base URL, as the reference does it.
///
/// The value is not parsed when it is already absolute: an authority marker takes `https:` whatever
/// the base scheme is, an `http` or `https` prefix is returned as it was read, and a value with a
/// scheme is returned as it was read. Only after those three answers is the base used, and the base
/// is parsed only when it has not been parsed already.
enum URLResolution {
    static func resolveToAbsolute(base: String, relative: String) throws -> String {
        try resolve(parsedBase: nil, base: base, relative: relative)
    }

    static func resolveToAbsolute(parsedBase: ParsedURL?, relative: String) throws -> String {
        try resolve(parsedBase: parsedBase, base: "", relative: relative)
    }

    private static func resolve(parsedBase: ParsedURL?, base: String, relative: String) throws -> String {
        if relative.hasPrefix("//") { return "https:" + relative }
        if hasHTTPPrefix(relative) { return relative }

        let parsedRelative = try ParsedURL.parse(relative)
        if parsedRelative.isAbsolute { return relative }

        if let parsedBase { return parsedBase.resolving(reference: parsedRelative).description }
        return try ParsedURL.parse(base).resolving(reference: parsedRelative).description
    }

    private static func hasHTTPPrefix(_ value: String) -> Bool {
        value.hasPrefix("https://") || value.hasPrefix("http://")
    }
}
