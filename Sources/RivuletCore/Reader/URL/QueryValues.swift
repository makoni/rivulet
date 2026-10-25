// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`url.Values`, `ParseQuery`, `Values.Encode`);
// adapted for Swift/SQLite.

import Foundation

/// The query as Go's `url.Values`: pairs decoded with `+` read as a space, and written back in
/// sorted key order, which is what makes the reference's output for the same input reproducible.
///
/// A malformed percent escape is skipped rather than failing the query, as `ParseQuery` does, so
/// the pairs that survive are the ones the reference keeps.
struct QueryValues: Equatable, Sendable {
    var values: [String: [String]] = [:]

    static func parse(_ rawQuery: String) -> QueryValues {
        var parsed = QueryValues()
        for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            // Go reports a semicolon inside a pair as an error, and `Query()` discards the pair.
            if pair.contains(";") { continue }

            // A pair with no separator is a key with an empty value.
            let keyPart: String
            let valuePart: String
            if let equals = pair.firstIndex(of: "=") {
                keyPart = String(pair[..<equals])
                valuePart = String(pair[pair.index(after: equals)...])
            } else {
                keyPart = String(pair)
                valuePart = ""
            }

            guard let key = try? URLEscaping.unescape(keyPart, mode: .queryComponent),
                let value = try? URLEscaping.unescape(valuePart, mode: .queryComponent) else { continue }
            parsed.values[key, default: []].append(value)
        }
        return parsed
    }

    /// Go's `Values.Encode`: keys sorted, each key and value written as a query component, where a
    /// space becomes `+`.
    func encode() -> String {
        if values.isEmpty { return "" }

        var pairs: [String] = []
        for key in values.keys.sorted() {
            let escapedKey = URLEscaping.escape(key, mode: .queryComponent)
            for value in values[key] ?? [] {
                pairs.append(escapedKey + "=" + URLEscaping.escape(value, mode: .queryComponent))
            }
        }
        return pairs.joined(separator: "&")
    }
}
