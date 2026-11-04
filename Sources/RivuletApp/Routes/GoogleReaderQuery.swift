// Ported from Go's `url.Values` as `r.URL.Query()` builds it, and from
// `internal/http/request/params.go` (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore

/// The query read the stream filter uses.
///
/// `r.URL.Query()` calls `url.ParseQuery` and discards the error it reports, so a pair that cannot
/// be read is skipped and the pairs after it are still read. That is the difference from the merged
/// form read, `GoogleReaderForm`, where the same pair ends the whole request: the handler answers
/// the error before it reads any value, so both sides agree at the API level while the pair rule is
/// per-pair here. `GoogleReaderQueryTests` pins which pairs are read, the order they answer in, and
/// the escape rules.
///
/// What this read cannot show: that a name the query does not carry and a name whose value is empty
/// answer the same, which is why the guards read the answer rather than the presence.
struct GoogleReaderQuery {
    /// The pairs that were read, in the order they came in.
    private let pairs: [(name: String, value: String)]

    init(query: String) {
        var pairs: [(name: String, value: String)] = []
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            // A pair that Go reports as an error for this read is skipped whole: `Query()` keeps
            // what parsed, so a name the read skipped is not in the map at all.
            guard let name = Self.unescape(String(parts[0])) else { continue }
            var value = ""
            if parts.count == 2 {
                guard let unescaped = Self.unescape(String(parts[1])) else { continue }
                value = unescaped
            }
            pairs.append((name, value))
        }
        self.pairs = pairs
    }

    /// `Values.Get`: the first value with this name, or the empty string for a name the query does
    /// not carry. Go's `Values` is a map, so the order is what the pins read per name.
    func value(named name: String) -> String {
        pairs.first { $0.name == name }?.value ?? ""
    }

    /// `Values[name]`, in the order the pairs came in.
    func values(named name: String) -> [String] {
        pairs.filter { $0.name == name }.map(\.value)
    }

    /// `request.QueryStringParam`: the default when the answer is empty.
    func string(named name: String, default defaultValue: String) -> String {
        let value = value(named: name)
        return value.isEmpty ? defaultValue : value
    }

    /// `request.QueryStringParamList`: the values trimmed with Go's `unicode.IsSpace`, with the
    /// empty ones skipped. This port's `.whitespaces` is a smaller set, so the control forms are
    /// what the two differ on, which the pins read.
    func list(named name: String) -> [String] {
        values(named: name).map { $0.trimmingCharacters(in: GoSpace.characters) }.filter { !$0.isEmpty }
    }

    /// `request.QueryIntParam`: the default for an empty, unparseable or negative value.
    func integer(named name: String, default defaultValue: Int) -> Int {
        let value = value(named: name)
        guard !value.isEmpty, let parsed = Int(value), parsed >= 0 else { return defaultValue }
        return parsed
    }

    /// `request.QueryInt64Param`, with the same three paths.
    func integer64(named name: String, default defaultValue: Int64) -> Int64 {
        let value = value(named: name)
        guard !value.isEmpty, let parsed = Int64(value), parsed >= 0 else { return defaultValue }
        return parsed
    }

    // MARK: - Rules

    /// A pair part as `parseQuery` reads it: Go's `unescape` for the escape rules, plus the `;`
    /// check the read makes for the pair, which is what `ParseForm` reports as
    /// `invalid semicolon separator`. Nothing is answered for a part that fails, which is the pair
    /// this read skips.
    private static func unescape(_ part: String) -> String? {
        guard !part.contains(";") else { return nil }
        return try? GoogleReaderForm.unescape(part)
    }
}
