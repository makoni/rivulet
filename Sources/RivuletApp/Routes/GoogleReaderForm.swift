// Ported from Go's `Request.ParseForm` and `Form.Get`, which the Google Reader path reads through
// `internal/googlereader/middleware.go` (Apache-2.0); adapted for Swift/SQLite.

/// The merged form the POST path reads.
///
/// The order is Go's: the urlencoded body pairs come first, then the query pairs, so the value this
/// read answers for a name both sides carry is the body one, which `GoogleReaderAuthTests` pins.
/// The body is part of the form only when the media type is `application/x-www-form-urlencoded` —
/// the caller decides that, and the same suite pins that a multipart body is not read.
///
/// What this read cannot show: that a name the form does not carry and a name whose value is empty
/// answer the same, which is why the guards read the answer rather than the presence, and that Go
/// reports the `;` error at the end of the read while keeping the pairs read before it, which this
/// read answers the same for.
struct GoogleReaderForm {
    /// What Go's `ParseForm` reports as an error for the whole form. Go has two, and both are the
    /// request failing here rather than one pair being skipped — the pins that put a readable value
    /// in one pair and the failure in another are what make this falsifiable.
    enum ReadError: Error, Equatable, Sendable {
        /// Go's `invalid semicolon separator in query`: a `;` is not a pair separator for
        /// `ParseForm`.
        case semicolonSeparator

        /// Go's `invalid URL escape`: a `%` that is not a two-digit hex escape.
        case malformedEscape
    }

    /// The pairs, in the order Go builds `r.Form` in: the body first, then the query.
    private let pairs: [(name: String, value: String)]

    /// Builds the form from the raw query and the body, both as the request carries them.
    ///
    /// - Throws: `ReadError` for what Go reports as an error for the whole form.
    init(query: String?, body: String?) throws {
        var pairs: [(name: String, value: String)] = []
        pairs.append(contentsOf: try Self.pairs(body))
        pairs.append(contentsOf: try Self.pairs(query))
        self.pairs = pairs
    }

    /// `r.Form.Get`: the first value with this name, or the empty string for a name the form does
    /// not carry.
    func value(named name: String) -> String {
        pairs.first { $0.name == name }?.value ?? ""
    }

    // MARK: - Rules

    /// Go's `parseQuery`: the pairs split on `&`, the empty ones skipped, and the name and the
    /// value each unescaped — a pair with no `=` is a name with an empty value.
    private static func pairs(_ raw: String?) throws -> [(name: String, value: String)] {
        guard let raw else { return [] }
        var pairs: [(name: String, value: String)] = []
        for pair in raw.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            if pair.contains(";") { throw ReadError.semicolonSeparator }
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(try Self.unescape(String(parts[0])))
            let value = parts.count == 2 ? String(try Self.unescape(String(parts[1]))) : ""
            pairs.append((name, value))
        }
        return pairs
    }

    /// Go's `unescape` as `parseQuery` uses it: `+` is a space, `%` starts a two-digit hex escape,
    /// and a `%` that is not one of those is the error this read reports for the whole form. The
    /// bytes are put back as UTF-8, which is what a percent-encoded value carries.
    private static func unescape(_ value: String) throws -> String {
        let scalars = value.unicodeScalars
        var bytes: [UInt8] = []
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "+" {
                bytes.append(UInt8(ascii: " "))
            } else if scalar == "%" {
                let first = scalars.index(after: index)
                guard first < scalars.endIndex, let high = Self.hexDigit(scalars[first]),
                    let low = Self.hexDigit(scalars[scalars.index(after: first)]) else {
                    throw ReadError.malformedEscape
                }
                bytes.append(high << 4 | low)
                index = scalars.index(first, offsetBy: 2)
                continue
            } else {
                bytes.append(contentsOf: String(scalar).utf8)
            }
            index = scalars.index(after: index)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A hex digit as `parseQuery` reads one, which accepts both cases, or nothing for a character
    /// that is not one.
    private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt8? {
        UInt8(String(scalar), radix: 16)
    }
}
