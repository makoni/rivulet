// Ported from Miniflux internal/googlereader/handler.go's checkOutputFormat (Apache-2.0); adapted
// for Swift/SQLite.

import Vapor

/// The output read the handlers of this path apply.
///
/// Which side is read is decided by the method, as the reference reads it: POST reads the merged
/// form, which is the read that reports a pair error for the whole form, and every other method
/// reads the query, which is the read that skips a pair it cannot parse. Only the value `json`
/// passes, compared as the read gives it. The endpoints this applies to are the handlers' choice,
/// and the status the answer writes for this error is the response builder's.
enum GoogleReaderOutput {
    /// What the read reports when the value is not `json`, which is the wording the 400 answer
    /// writes.
    enum CheckError: Error, CustomStringConvertible, Sendable {
        case onlyJSON

        var description: String { "googlereader: only json output is supported" }
    }

    /// `checkOutputFormat`.
    ///
    /// - Throws: `CheckError` for a value that is not `json`, or the pair error the form read
    /// reports for the whole form. The query read has no such error, because it skips the pair.
    static func check(method: HTTPMethod, query: String, body: String?) throws {
        let value: String
        if method == .POST {
            value = try GoogleReaderForm(query: query, body: body).value(named: "output")
        } else {
            value = GoogleReaderQuery(query: query).value(named: "output")
        }
        guard value == "json" else { throw CheckError.onlyJSON }
    }
}
