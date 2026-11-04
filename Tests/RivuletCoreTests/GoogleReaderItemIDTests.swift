import Testing
@testable import RivuletCore

/// The item id rules the Google Reader router reads: `internal/googlereader/item.go` at `c4d54f87`.
/// The goldens below are the reference's own output for the same inputs at the toolchain `go.mod`
/// pins, including the error wording, which is what the 500 answer writes.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the four input
/// forms — the long form with padding, the long form without it, the bare 16-character hex form,
/// and the decimal form — which a patch that reads only one of them fails; the prefix that chooses
/// the form, which a patch that treats the prefix as part of the number fails; the 16-character
/// length that makes the bare form hex, which a patch that reads any length as hex fails on
/// `12345`; the hex scan as Go's `fmt.Sscanf` reads it — the field width is 16, the sign is
/// optional, the digits stop at the first character that is not a hex digit, and what was read is
/// kept — which a patch that required the whole value to be a hex number fails on
/// `.../0000000000000001x`, and a patch that read `0x` as the base prefix fails on
/// `0x0000000000000f`, where the scan answers the single character `0`; that the hex read is tried
/// before the decimal one and its failure falls through, which a patch that answered the hex error
/// fails on `8000000000000000`; the zero check that belongs only to the long form, which a patch
/// that applied it to the bare hex form fails on `000000000000000g`; the decimal read as
/// `strconv.ParseInt` reads it, which a patch that read the decimal form as hex and read its
/// characters as hex digits fails on `g000000000000000`, and which answers the most negative value
/// as an answer rather than as out of range; the 16-digit width of the hex write, which a patch
/// that wrote without padding fails, and its lowercase form, which a patch that wrote it uppercase
/// fails; the sign the write puts before the padding, which a patch that gave the digits the whole
/// width fails on `entryID: -1`; the space `fmt.Sscanf` skips before the field, which a patch that
/// did not skip it fails on `.../item/ 1`, and that the skipped space does not count against the
/// field width, which a patch that counted it fails on `.../item/ 12345678901234567`; that a
/// newline is not a space the scan skips, which a patch that skipped it fails on `.../item/\n1`,
/// where the reference reports "unexpected newline"; that the scan reads per Unicode scalar, which
/// a patch that tested the whole grapheme as a hex digit fails on `.../item/0\u{0301}`; and each
/// error wording, including that the hex wording names the token the scan read rather than the
/// whole input, which a patch that wrote the whole input fails on `.../8000000000000000x`.
///
/// What these pins cannot fail on: that `fmt.Sscanf` reports one scanned value, which has no input
/// that can fail here — the count is 1 for every value the scan reads; and the rule that a form
/// with no item ids is an error, which belongs to the handler and is pinned with it.
@Suite struct GoogleReaderItemIDTests {
    private func errorDescription(for value: String) -> String? {
        do {
            _ = try GoogleReaderItemID.parse(value)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test func theLongFormWriteIsTheReferenceFormat() throws {
        #expect(GoogleReaderItemID.longForm(entryID: 344691561) ==
            "tag:google.com,2005:reader/item/00000000148b9369", "the reference's output for the same value")
        #expect(GoogleReaderItemID.longForm(entryID: 15) ==
            "tag:google.com,2005:reader/item/000000000000000f", "padded to 16 digits, written in lowercase")
        #expect(GoogleReaderItemID.longForm(entryID: 4096) ==
            "tag:google.com,2005:reader/item/0000000000001000", "the width is 16 digits")
        #expect(GoogleReaderItemID.longForm(entryID: 1) ==
            "tag:google.com,2005:reader/item/0000000000000001", "and the value 1 is still padded")
        #expect(GoogleReaderItemID.longForm(entryID: -1) ==
            "tag:google.com,2005:reader/item/-000000000000001",
            "the sign is written before the padding, so the digits fill what the field width leaves")
    }

    @Test func theFourInputFormsAreRead() throws {
        #expect(try GoogleReaderItemID.parse("12345") == 12345, "the decimal form, which is read last")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/00000000148b9369") == 344691561,
            "the long form with the padding, which is what the reference writes")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/2f2") == 754,
            "the long form without the padding")
        #expect(try GoogleReaderItemID.parse("000000000000046f") == 1135, "the bare 16-character hex form")
        #expect(try GoogleReaderItemID.parse("1234567890123456") == 1311768467284833366,
            "16 characters are read as hex, which is a different value from the decimal read")

        // The scan reads at most 16 characters and does not treat `0x` as the base prefix, so this
        // is the single character `0`, not 15.
        #expect(try GoogleReaderItemID.parse("0x0000000000000f") == 0, "the scan reads the `0` and stops")
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/0x10") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/0x10: item ID is zero",
            "and the zero check is what the long form answers for it")

        // A sign is part of the scan, and it counts against the field width, so this is 15 digits.
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/+2f2") == 754, "the sign")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/-1") == -1, "the negative sign")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/-1000000000000000") ==
            -72057594037927936, "the sign is inside the 16-character field")

        // Go's `len()` counts bytes, so this 15-character value is 16 bytes and is the hex form: a
        // patch that compared Swift's `count` answered the decimal error here.
        #expect(try GoogleReaderItemID.parse("00000000000000é") == 0, "16 bytes, 15 characters")

        // The hex read is tried first for a 16-character value, and when it fails the decimal read
        // answers.
        #expect(try GoogleReaderItemID.parse("8000000000000000") == 8000000000000000,
            "the hex scan is out of range here, so the decimal read answers it")
        #expect(try GoogleReaderItemID.parse("+12345") == 12345, "the decimal read accepts a sign")
        #expect(try GoogleReaderItemID.parse("-9223372036854775808") == -9223372036854775808,
            "the most negative value is an answer for the decimal read, not out of range")
    }

    @Test func theScanSkipsTheSpaceBeforeTheField() throws {
        // `fmt.Sscanf` skips the space before a verb before reading the field, so these are the
        // digits after the space, and the skipped space does not count against the field width.
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/ 1") == 1,
            "the value after a skipped space")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/\t1") == 1,
            "the tab is skipped the same way")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/\u{85}1") == 1,
            "and so is the next line, which is a space for the reference's character set")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/ 12345678901234567") ==
            1311768467284833366, "the field width counts what is read, not the skipped space")

        // A newline is not a space the scan skips, so it is what the read reports where a space
        // would have been skipped.
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/\n1") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/\n1: " +
            "unexpected newline", "the newline is not skipped")
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/ \n1") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/ \n1: " +
            "unexpected newline", "the space is skipped first, so the newline is what is read")

        // A field that is only whitespace runs out before anything is read, which is what Go
        // reports as EOF.
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/ ") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/ : EOF",
            "a field that is only a space")

        // The sign is read after the skip, and the space after it is not skipped again, so the
        // digits that follow are not read as part of the same number.
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/+ 1") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/+ 1: expected integer",
            "the sign is not followed by a digit")

        // 16 bytes with the space at the front is the bare hex form, so the scan reads the 15
        // digits after the skipped space.
        #expect(try GoogleReaderItemID.parse(" 123456789012345") == 81985529205302085,
            "the bare form reads the digits after the skipped space")
    }

    @Test func theScanReadsOneUnicodeScalarAtATime() throws {
        // The scan reads runes, not the grapheme cluster this port's `Character` is, so the base
        // character is what is read and the combining mark stops it: a patch that tested the whole
        // character as a hex digit answered "expected integer" here instead of the zero.
        #expect(errorDescription(for: "tag:google.com,2005:reader/item/0\u{0301}") ==
            "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/0\u{0301}: " +
            "item ID is zero", "the scalar `0` is read, and the long form reports the zero")
    }

    @Test func theHexScanStopsAtTheFirstCharacterThatIsNotADigit() throws {
        // The field width is 16, so the scan reads `0000000000000001` and stops before the `x`. A
        // patch that required the whole value to be a hex number answered nothing here.
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/0000000000000001x") == 1,
            "the scan stops at the first character that is not a digit")

        // 17 characters are not the bare hex form, so the decimal read is what fails.
        #expect(errorDescription(for: "00000000148b9369x") ==
            "failed to parse decimal item ID 00000000148b9369x: strconv.ParseInt: parsing " +
            "\"00000000148b9369x\": invalid syntax", "17 characters are neither the hex form nor a number")

        // The scan keeps what it read, so 15 digits give zero, and the zero check does not belong
        // to the bare form: a patch that applied it reported the error here.
        #expect(try GoogleReaderItemID.parse("000000000000000g") == 0, "the bare hex form has no zero check")
        #expect(errorDescription(for: "g000000000000000") ==
            "failed to parse decimal item ID g000000000000000: strconv.ParseInt: parsing " +
            "\"g000000000000000\": invalid syntax",
            "16 characters that are not hex are not the hex form, and the decimal read fails too")
    }

    @Test func theErrorWordingMatchesTheReferenceOutput() throws {
        let goldens: [(String, String)] = [
            ("tag:google.com,2005:reader/item/000000000000000g",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/000000000000000g: " +
                "item ID is zero"),
            ("tag:google.com,2005:reader/item/00000000000000000",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/00000000000000000: " +
                "item ID is zero"),
            ("tag:google.com,2005:reader/item/",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/: EOF"),
            ("tag:google.com,2005:reader/item/-",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/-: EOF"),
            ("tag:google.com,2005:reader/item/g",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/g: expected integer"),
            // The part after the prefix is the whole input here, so the two wordings are the same
            // string.
            ("tag:google.com,2005:reader/item/8000000000000000",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/8000000000000000: " +
                "strconv.ParseInt: parsing \"8000000000000000\": value out of range"),
            // The scan read 16 of these 17 characters, so the wording names the token it read, not
            // the whole input: a patch that wrote the whole input fails on this row.
            ("tag:google.com,2005:reader/item/8000000000000000x",
                "failed to parse hexadecimal item ID tag:google.com,2005:reader/item/8000000000000000x: " +
                "strconv.ParseInt: parsing \"8000000000000000\": value out of range"),
            ("invalid_id",
                "failed to parse decimal item ID invalid_id: strconv.ParseInt: parsing " +
                "\"invalid_id\": invalid syntax"),
            ("", "failed to parse decimal item ID : strconv.ParseInt: parsing \"\": invalid syntax"),
            ("0x10", "failed to parse decimal item ID 0x10: strconv.ParseInt: parsing \"0x10\": invalid syntax"),
            ("1e3", "failed to parse decimal item ID 1e3: strconv.ParseInt: parsing \"1e3\": invalid syntax"),
            (" 12345",
                "failed to parse decimal item ID  12345: strconv.ParseInt: parsing \" 12345\": invalid syntax"),
            ("1_000",
                "failed to parse decimal item ID 1_000: strconv.ParseInt: parsing \"1_000\": invalid syntax"),
        ]
        for (input, expected) in goldens {
            #expect(errorDescription(for: input) == expected, "the wording the 500 answer writes for \(input)")
        }
    }

    @Test func anItemIDThatReadsAValueHasNoError() throws {
        #expect(errorDescription(for: "12345") == nil, "the decimal form answers a value")
        #expect(errorDescription(for: "0000000000000000") == nil,
            "zero is an answer for the bare form, not an error")
        #expect(try GoogleReaderItemID.parse("tag:google.com,2005:reader/item/7fffffffffffffff") ==
            9223372036854775807, "the largest value the scan reads is still an answer")
    }
}
