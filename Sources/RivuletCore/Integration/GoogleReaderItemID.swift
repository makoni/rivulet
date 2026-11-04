// Ported from Miniflux internal/googlereader/item.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The item id the Google Reader contract uses.
///
/// Upstream writes it as `ItemIDFormat` — the prefix, then the value as 16 lowercase hex digits —
/// and reads it back in four forms: the long form, the same value without the padding, a bare value
/// that is exactly 16 characters long, and a decimal number. The last two are what the clients that
/// do not follow the reference's own write send, which is why the bare 16-character form is read as
/// hex before the decimal read is tried. `GoogleReaderItemIDTests` pins each form, the width and
/// the case of the write, and the wording the 500 answer writes.
///
/// The hex read is `fmt.Sscanf` with `%016x`, not a whole-value hex parse: the sign is optional,
/// the `0x` prefix is not read as the base marker, the digits stop at the first character that is
/// not one, and what was read is kept, so `.../0000000000000001x` is 1 and `0x0000000000000f` is 0.
/// The zero check belongs to the long form only, so the bare form answers zero for
/// `000000000000000g`.
public enum GoogleReaderItemID {
    /// `ItemIDPrefix`, which chooses the form the value is read as.
    public static let prefix = "tag:google.com,2005:reader/item/"

    /// The field width `%016x` gives the scan, which counts the sign.
    private static let fieldWidth = 16

    /// What the reference reports for a value that cannot be read, which is the wording the 500
    /// answer writes. The part after the input names the token the read used, which for the hex
    /// form is what the scan read rather than the whole value.
    public struct ReadError: Error, CustomStringConvertible, Sendable {
        /// Which read reported it: the hex scan or the decimal one.
        public enum Form: String, Sendable {
            case hexadecimal
            case decimal
        }

        public let form: Form
        public let input: String
        public let reason: String

        public var description: String {
            "failed to parse \(form.rawValue) item ID \(input): \(reason)"
        }
    }

    /// `convertEntryIDToLongFormItemID`.
    public static func longForm(entryID: Int64) -> String {
        // Go writes the sign before the padding, so the digits fill what is left of the field
        // width.
        let width = entryID < 0 ? fieldWidth - 1 : fieldWidth
        var digits = String(entryID.magnitude, radix: 16)
        if digits.count < width {
            digits = String(repeating: "0", count: width - digits.count) + digits
        }
        return prefix + (entryID < 0 ? "-" : "") + digits
    }

    /// Reads one item id as the reference reads it.
    ///
    /// - Throws: `ReadError`, with the reference's wording.
    public static func parse(_ value: String) throws -> Int64 {
        if value.hasPrefix(prefix) {
            let scanned = try scan(field: String(value.dropFirst(prefix.count)), input: value)
            if scanned == 0 {
                throw ReadError(form: .hexadecimal, input: value, reason: "item ID is zero")
            }
            return scanned
        }

        // Go's `len()` counts bytes, so a value with a character that needs more than one byte is a
        // different length here than for Swift's `count`.
        if value.utf8.count == fieldWidth, let scanned = try? scan(field: value, input: value) {
            return scanned
        }

        return try parseDecimal(value)
    }

    // MARK: - Rules

    /// `fmt.Sscanf` with `%016x`: the sign, then digits up to the field width, stopping at the
    /// first character that is not one. Go reports EOF when there is nothing to scan and "expected
    /// integer" when the character there is not one, and the value is what `strconv.ParseInt`
    /// answers for the token the scan read.
    private static func scan(field: String, input: String) throws -> Int64 {
        let characters = Array(field)
        var position = 0
        var negative = false
        if position < characters.count, characters[position] == "-" || characters[position] == "+" {
            negative = characters[position] == "-"
            position += 1
        }

        var digits = ""
        while position < characters.count, position < fieldWidth, isHexDigit(characters[position]) {
            digits.append(characters[position])
            position += 1
        }

        if digits.isEmpty {
            // Go reports EOF when the input ran out, which is what a field that is only a sign is,
            // and "expected integer" when the character there is not one.
            throw ReadError(form: .hexadecimal, input: input,
                reason: position == characters.count ? "EOF" : "expected integer")
        }
        guard let scanned = Int64(digits, radix: 16) else {
            throw ReadError(form: .hexadecimal, input: input,
                reason: "strconv.ParseInt: parsing \"\(digits)\": value out of range")
        }
        return negative ? -scanned : scanned
    }

    /// `strconv.ParseInt` with base 10, which is what answers for a value that is not the hex form.
    private static func parseDecimal(_ value: String) throws -> Int64 {
        let digits = value.dropFirst(value.hasPrefix("-") || value.hasPrefix("+") ? 1 : 0)
        if digits.isEmpty || !digits.allSatisfy(isDigit) {
            throw ReadError(form: .decimal, input: value,
                reason: "strconv.ParseInt: parsing \"\(value)\": invalid syntax")
        }
        guard let parsed = Int64(value) else {
            throw ReadError(form: .decimal, input: value,
                reason: "strconv.ParseInt: parsing \"\(value)\": value out of range")
        }
        return parsed
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        character.isHexDigit
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
