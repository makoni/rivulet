// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`url.Parse`); adapted for Swift/SQLite.

import Foundation

/// Why a value does not parse. The cases name what the reference reports; the wording is not Go's,
/// because Go returns `errors.New` strings, and the reader acts on the failure, not on the text.
enum URLParseError: Error, Equatable, Sendable {
    /// Go reports this as "missing protocol scheme": a colon at the start of the value.
    case missingScheme

    /// A character before the colon that is not a scheme character, which for Go means there is no
    /// scheme at all; this port reports it as an error only when the reader needs a scheme.
    case invalidScheme(String)

    /// A relative value whose first path segment contains a colon.
    case colonInFirstSegment(String)

    /// Go reports the offending character in the host.
    case invalidHost(character: Character)

    /// A bracketed host that is not closed.
    case unclosedBracketHost

    case invalidPort(String)

    /// Go reports "invalid control character in URL", which is a byte below ` ` or `DEL`.
    case controlCharacter(Character)

    case invalidEscape(String)
}
