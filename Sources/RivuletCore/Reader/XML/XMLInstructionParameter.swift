// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The helper is the
// `procInst` of `encoding/xml`.

import Foundation

/// A parameter of a processing instruction, read the way `encoding/xml` reads it — the reference's own
/// comment calls this parsing "somewhat lame and not exact", but it is what the reference does.
enum XMLInstructionParameter {
    /// The unquoted value of `name` in the content of an instruction, or `nil` when the content does
    /// not carry it, which is the empty string the reference returns.
    static func value(of name: String, in content: String) -> String? {
        guard let marker = content.range(of: name + "=") else { return nil }
        let value = content[marker.upperBound...]
        guard let quote = value.first, quote == "'" || quote == "\"" else { return nil }
        guard let end = value.dropFirst().range(of: String(quote)) else { return nil }
        return String(value.dropFirst().prefix(upTo: end.lowerBound))
    }
}
