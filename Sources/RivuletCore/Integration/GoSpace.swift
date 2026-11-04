// Ported from Go's `unicode.IsSpace` (Apache-2.0, the Go standard library); adapted for
// Swift/SQLite.

import Foundation

/// The characters the reference treats as space, which is the set both rules that read whitespace
/// use: `strings.TrimSpace` for the list read, and the space `fmt.Sscanf` skips before a verb. It
/// is not this port's `.whitespaces`, which does not have the control forms, so the pins read the
/// characters the two sets differ on.
public enum GoSpace {
    /// `unicode.IsSpace` for one character.
    public static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        characters.contains(scalar)
    }

    /// The same set as a character set, for the read that trims with one.
    public static let characters: CharacterSet = {
        var set = CharacterSet()
        for code in codePoints {
            guard let scalar = Unicode.Scalar(code) else { continue }
            set.insert(scalar)
        }
        return set
    }()

    /// The code points `unicode.IsSpace` answers for, as the Go package lists them.
    private static let codePoints: [UInt32] = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ] + Array(0x2000...0x200A)
}
