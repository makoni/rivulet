// Ported from Miniflux internal/http/request/params.go's `QueryBoolParam` (Apache-2.0); adapted for
// Swift/SQLite.

/// The query read this path uses, built on the pair read `GoogleReaderQuery` pins.
enum RestV1Query {
    /// `QueryBoolParam`: a name the query does not carry answers the default, and a value the parse
    /// fails on answers the default too. The parse admits the two digits, the four words in the three
    /// cases the reference writes, and the two single letters, and nothing else.
    static func boolean(named name: String, default value: Bool, from query: String) -> Bool {
        let read = GoogleReaderQuery(query: query).value(named: name)
        switch read {
        case "1", "t", "T", "true", "TRUE", "True": return true
        case "0", "f", "F", "false", "FALSE", "False": return false
        default: return value
        }
    }
}
