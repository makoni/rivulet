// Ported from Go's `Request.ParseForm` and `Request.FormValue`, which the Fever path reads through
// `internal/fever/middleware.go` (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore

/// The merged form as `r.Form` ends up holding it.
///
/// Three sources, in the order Go builds `r.Form` from them per name: the urlencoded body pairs,
/// then the query pairs, then the value parts of a multipart body. So the answer this read gives
/// for a name carried by two sources is the first one added, which is what `FormValue` takes.
///
/// The read reports no error, and that is the rule the handler reads: `FormValue` discards what
/// `ParseMultipartForm` reports, so a body this read cannot read adds nothing and the guard that
/// reads the key answers the empty value rather than a failure — the answer is the auth failure
/// document, not the shape the Google Reader path answers for a form it cannot parse. The pair
/// rules are the `parseQuery` ones, which `GoogleReaderQuery` pins: a pair with a `;` or a bad
/// escape is skipped and the pairs after it are still read. What this read cannot show: Go's 10 MB
/// memory threshold and its 1000-part cap, which nothing here reaches; the `filename` value as
/// `filepath.Base` cuts it, which only the file half uses; and the order across names, which Go
/// reads through a map, so the pins read one name at a time.
struct FeverForm: Sendable {
    /// The values `r.Form` holds, grouped by name in the order the read added them.
    private let pairsByName: [String: [String]]

    /// Builds the form from what the request carries. The method decides whether an urlencoded body
    /// is part of the form, and the content type decides whether the body is a multipart one.
    init(method: String, contentType: String?, query: String?, body: String?) {
        var names: [String: [String]] = [:]
        func add(_ name: String, _ value: String) { names[name, default: []].append(value) }

        // `ParseForm` copies `PostForm` before the query pairs, and `ParseMultipartForm` appends
        // its values after both.
        if Self.readsBodyHalf(method), FeverMultipartRead.mediaType(contentType ?? "")?.type
            == "application/x-www-form-urlencoded", let body {
            for pair in GoogleReaderQuery(query: body).pairs { add(pair.name, pair.value) }
        }
        for pair in GoogleReaderQuery(query: query ?? "").pairs { add(pair.name, pair.value) }
        for part in FeverMultipartRead.parts(contentType: contentType ?? "", body: body ?? "") ?? [] {
            add(part.name, part.value)
        }

        pairsByName = names
    }

    /// `r.Form.Get`, which is what `FormValue` answers: the first value with this name, or the
    /// empty string for a name the form does not carry.
    func value(named name: String) -> String {
        pairsByName[name]?.first ?? ""
    }

    /// `r.Form[name]`, in the order the read added the values.
    func values(named name: String) -> [String] {
        pairsByName[name] ?? []
    }

    /// `request.FormInt64Value`: the parsed value, or 0 for one this read cannot read.
    func integer64(named name: String) -> Int64 {
        (try? GoParseInt.parse(value(named: name))) ?? 0
    }

    // MARK: - Rules

    /// The three methods `ParseForm` reads a body for. The multipart half is read whatever the
    /// method is, because `FormValue` goes through `ParseMultipartForm`, so this guard belongs to
    /// the urlencoded half only.
    private static func readsBodyHalf(_ method: String) -> Bool {
        method == "POST" || method == "PUT" || method == "PATCH"
    }
}
