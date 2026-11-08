// Ported from Go's `Request.ParseForm` and `Form.Get`, which the Google Reader path reads through
// `internal/googlereader/middleware.go` (Apache-2.0); adapted for Swift/SQLite.

/// The merged form the POST path reads.  The order is Go's: the urlencoded body pairs come
/// first, then the query pairs, so the value this read answers for a name both sides carry is
/// the body one, which `GoogleReaderAuthTests` pins. The body is part of the form only when the
/// media type is `application/x-www-form-urlencoded` — the caller decides that, and the same
/// suite pins that a multipart body is not read.  The answer for a name has two halves, and
/// this read keeps them apart: `value(named:)` is what Go's `Form.Get` answers, which is the
/// empty string for a name the form does not carry and for a name it carries with an empty
/// value, while `has(named:)` is Go's `Values.Has`, which answers differently for those two.
/// The guards that read the answer are the ones that cannot tell the halves apart; the one
/// guard that reads the presence is `subscription/edit`, and the pin that shows the difference
/// is there.  What this read cannot show: that Go reports the `;` error at the end of the read
/// while keeping the pairs read before it, which this read answers the same for, and the escape
/// wording, which `docs/parity.md` records as the quoting divergence.
struct GoogleReaderForm {
    /// What Go's `ParseForm` reports as an error for the whole form. The pair-level errors are two,
    /// and both are the request failing here rather than one pair being skipped — the pins that put
    /// a readable value in one pair and the failure in another are what make this falsifiable. Go's
    /// other `ParseForm` errors, a media type it cannot parse and a body over its 10 MB cap, have
    /// nothing to fail on in this suite.
    ///
    /// The wordings are the ones the answer writes, and the escape one names the text Go names: the
    /// substring from the percent, cut to three characters. Go builds that sentence with `%q`,
    /// which is the quoting divergence `docs/parity.md` records; the pins read the cases where it
    /// makes no difference, because the text a failing escape names is the percent and the
    /// characters after it.
    enum ReadError: Error, CustomStringConvertible, Equatable, Sendable {
        /// Go's `invalid semicolon separator in query`: a `;` is not a pair separator for
        /// `ParseForm`.
        case semicolonSeparator

        /// Go's `invalid URL escape`, with the text Go names.
        case malformedEscape(String)

        var description: String {
            switch self {
            case .semicolonSeparator: return "invalid semicolon separator in query"
            case .malformedEscape(let escape): return "invalid URL escape \"\(escape)\""
            }
        }
    }

    /// The pairs, in the order Go builds `r.Form` in: the body first, then the query.
    private let pairs: [(name: String, value: String)]

    /// The pairs Go builds `r.PostForm` from, without the query pairs. `edit-tag` reads `a` and `r`
    /// through this side, while `i` is read through `r.Form`.
    private let postPairs: [(name: String, value: String)]

    /// Builds the form from the raw query and the body, both as the request carries them.
    ///
    /// - Throws: `ReadError` for what Go reports as an error for the whole form.
    init(query: String?, body: String?) throws {
        let postPairs = try Self.pairs(body)
        var pairs = postPairs
        pairs.append(contentsOf: try Self.pairs(query))
        self.postPairs = postPairs
        self.pairs = pairs
    }

    /// `r.Form.Get`: the first value with this name, or the empty string for a name the form does
    /// not carry. Go's `r.Form` is a map, so what this order gives is the answer per name, not the
    /// order the pairs are read in overall.
    func value(named name: String) -> String {
        pairs.first { $0.name == name }?.value ?? ""
    }

    /// `r.Form[name]`, in the order the merged pairs were built.
    func values(named name: String) -> [String] {
        pairs.filter { $0.name == name }.map(\.value)
    }

    /// `r.Form.Has(name)`: whether the form carries the name at all. A pair with no `=` is a name
    /// with an empty value, so this answers `true` for a name the value read answers the empty
    /// string for — the two halves `subscription/edit` reads apart, which is what that suite's pin
    /// shows.
    func has(named name: String) -> Bool {
        pairs.contains { $0.name == name }
    }

    /// `r.PostForm[name]`, in the order the body pairs came in.
    func postValues(named name: String) -> [String] {
        postPairs.filter { $0.name == name }.map(\.value)
    }

    // MARK:
    // - Rules

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
    /// and a `%` that is not one of those is the error this read reports for the whole form — the
    /// same pair is skipped instead by `GoogleReaderQuery`, which is `r.URL.Query()`. The bytes are
    /// put back as UTF-8, so an escape whose bytes are not valid UTF-8 answers U+FFFD here, where
    /// Go keeps the byte it could not decode — the divergence `docs/parity.md` records.
    static func unescape(_ value: String) throws -> String {
        let scalars = value.unicodeScalars
        var bytes: [UInt8] = []
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "+" {
                bytes.append(UInt8(ascii: " "))
            } else if scalar == "%" {
                // Go checks that both characters of the escape are there before reading them, so
                // the bounds are read before either character: for an escape that runs off the end
                // of the pair there is nothing to read, which is the error this read reports.
                let first = scalars.index(after: index)
                guard first < scalars.endIndex else {
                    throw ReadError.malformedEscape(Self.namedEscape(scalars, from: index))
                }
                let second = scalars.index(after: first)
                guard second < scalars.endIndex, let high = Self.hexDigit(scalars[first]),
                    let low = Self.hexDigit(scalars[second]) else {
                    throw ReadError.malformedEscape(Self.namedEscape(scalars, from: index))
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

    /// The text the escape error names: the substring from the percent, cut to three. Go cuts three
    /// bytes; this cuts three characters, so a multi-byte character is cut whole here, which is the
    /// divergence `docs/parity.md` records.
    private static func namedEscape(_ scalars: String.UnicodeScalarView, from index: String.Index) -> String {
        var bytes: [UInt8] = []
        var position = index
        while position < scalars.endIndex, bytes.count < 3 {
            bytes.append(contentsOf: String(scalars[position]).utf8)
            position = scalars.index(after: position)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A hex digit as `parseQuery` reads one, which accepts both cases, or nothing for a character
    /// that is not one.
    private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt8? {
        UInt8(String(scalar), radix: 16)
    }
}
