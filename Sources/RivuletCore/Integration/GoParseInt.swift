// Ported from Go's `strconv.ParseInt(value, 10, 64)`, which the Google Reader path calls for `ts`,
// for the decimal form of an item id and for the part left after the `feed/` prefix (Apache-2.0);
// adapted for Swift/SQLite.

/// The base-10 integer read the reference uses in three places of this path.
///
/// The sign is part of the value the read takes, `0x` is not the base marker, and a space before
/// the digits is the error rather than something to skip — which is what `GoSpace` skips for the
/// scan that reads the hexadecimal form. The wording is the reference's, so this is the one place
/// it is written.
public enum GoParseInt {
    /// What the read reports for a value it cannot read.
    public enum ParseError: Error, CustomStringConvertible, Sendable {
        case invalidSyntax(String)
        case outOfRange(String)

        /// The wording the reference reports for whichever half the value is, which is why this read
        /// writes it rather than the call sites.
        public var description: String {
            switch self {
            case .invalidSyntax(let value):
                return "strconv.ParseInt: parsing \"\(value)\": invalid syntax"
            case .outOfRange(let value):
                return "strconv.ParseInt: parsing \"\(value)\": value out of range"
            }
        }
    }

    /// `strconv.ParseInt(value, 10, 64)`.
    ///
    /// - Throws: ``ParseError`` for a value this read cannot read.
    public static func parse(_ value: String) throws -> Int64 {
        let digits = value.dropFirst(value.hasPrefix("-") || value.hasPrefix("+") ? 1 : 0)
        if digits.isEmpty || !digits.allSatisfy(isDigit) {
            throw ParseError.invalidSyntax(value)
        }
        guard let parsed = Int64(value) else {
            throw ParseError.outOfRange(value)
        }
        return parsed
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
