// Ported from Go's `encoding/json` encoder, which `internal/http/response.JSON` writes through
// (Apache-2.0); adapted for Swift/SQLite.

/// The document the client APIs write.
///
/// This is `json.Marshal`, not `JSONEncoder`: the reference writes the compact form with no spaces,
/// keeps the object's keys in the order the document declares them, and does not escape a solidus —
/// which is where Swift's own encoder differs. The escape classes are the reference's: the quote
/// and the backslash, the three control characters that have a short form, every other character
/// below U+0020, the three HTML-sensitive ones, and the two line separators. `JSONValueTests` pins
/// each class against the reference's output, and the key order with an input where an alphabetical
/// write would differ.
enum JSONValue {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case null
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    /// What `json.Marshal` writes for this document.
    func written() -> String {
        switch self {
        case .string(let value):
            return Self.quote(value)
        case .integer(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return "[" + values.map { $0.written() }.joined(separator: ",") + "]"
        case .object(let pairs):
            return "{" + pairs.map { Self.quote($0.key) + ":" + $0.value.written() }
                .joined(separator: ",") + "}"
        }
    }

    /// `encoder.encodeString`: the quote, the backslash, the three control characters written with
    /// their short forms, every other character below U+0020 as `\u00XX`, the three HTML-sensitive
    /// characters and the two line separators as `\uXXXX` with lowercase digits, and everything
    /// else as it is. A Swift `String` always holds valid UTF-8, so the reference's case of an
    /// invalid byte becoming `\ufffd` cannot arise here; a valid U+FFFD is written as it is, which
    /// is what the reference does for one.
    private static func quote(_ value: String) -> String {
        var written = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": written += "\\\""
            case "\\": written += "\\\\"
            case "\t": written += "\\t"
            case "\n": written += "\\n"
            case "\r": written += "\\r"
            case "&", "<", ">", "\u{2028}", "\u{2029}":
                written += Self.escaped(scalar)
            default:
                written += scalar.value < 0x20 ? Self.escaped(scalar) : String(scalar)
            }
        }
        return written + "\""
    }

    /// `\u` and four lowercase hex digits.
    private static func escaped(_ scalar: Unicode.Scalar) -> String {
        "\\u" + String(format: "%04x", scalar.value)
    }
}
