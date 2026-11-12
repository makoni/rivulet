import Foundation
import Testing
@testable import RivuletCore

/// The version value as the program and its clients read it.
///
/// (ported test: `TestVersionConvertedToInteger`, `internal/version/version_test.go`.)
///
/// What the pins can fail on, each checked by patching the value and reverting the file
/// byte-identically: that the value is not empty, and that the digits it carries read as a
/// positive integer. The three crafts are a value with no digit at all, which fires the digit
/// presence half, whose conversion half can fire on it only as a consequence of that same empty
/// digit set; a value whose digits are all zero, which fires the sign guard alone; and a value
/// patched to the empty string, which fires the presence pin and reaches the digit pin, because
/// both read the same value. Single-firing holds only for the all-zero craft, which is the craft
/// that names the sign guard.
/// The two halves of the digit pin are read in that order, as the ported test reads them: the empty
/// digit set is reported before the conversion.
///
/// What these pins cannot fail on: the conversion itself, which no code in this port performs — a
/// client does it, so the pin reads the value as data rather than through a rule the port has; the
/// digit class, which is Unicode category Nd, what `CharacterSet.decimalDigits` is, read per
/// Unicode scalar, because a value that could tell Swift's `isNumber` — which reads categories Nl
/// and No as well — apart from the reference's class is not a version this port carries; and the
/// fallback wording the reference gives a value that is empty, which this port has no branch for.
@Suite struct RivuletCoreTests {
    @Test func versionIsPresent() {
        #expect(!RivuletCore.version.isEmpty)
    }

    @Test func versionDigitsReadAsAPositiveInteger() throws {
        let decimalDigits = CharacterSet.decimalDigits
        let digits = RivuletCore.version.unicodeScalars.filter(decimalDigits.contains)
        let read = String(digits.map(String.init).joined())

        #expect(!read.isEmpty, "the version carries no digit a client can read")

        let asInteger = try #require(Int(read), "the digits \(read) are not a number")
        #expect(asInteger > 0, "the digits \(read) read as \(asInteger)")
    }
}
