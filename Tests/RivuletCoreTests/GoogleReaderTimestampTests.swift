import Testing
@testable import RivuletCore

/// The `ts` read `markAllAsReadHandler` builds its `before` from.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the empty value
/// answers the default rather than a time, the length test is the length of the value as read, the
/// two units the same digits give at the two sides of that length, the sign guard that a value
/// which is not positive leaves the default, and the wording the read reports.
///
/// What these pins cannot fail on: the part below a second. The reference builds a `time.Time`, and
/// this port's entry column holds whole seconds, so a microsecond value that is not a whole number
/// of seconds cannot be told from its truncated form here; the second boundary itself is pinned by
/// the storage read, which uses `<`.
@Suite struct GoogleReaderTimestampTests {
    @Test func anEmptyValueAnswersTheDefault() async throws {
        #expect(try GoogleReaderTimestamp.before(value: "", now: 500) == 500)
        #expect(try GoogleReaderTimestamp.before(value: nil, now: 500) == 500)
    }

    @Test func theLengthOfTheValueAsReadDecidesTheUnit() async throws {
        // Fifteen characters are the seconds side, sixteen the microsecond side, and the test is
        // the length of the value as the form read gave it, not the number of digits of the parsed
        // value.
        #expect(try GoogleReaderTimestamp.before(value: "100000000000000", now: 500) == 100_000_000_000_000)
        #expect(try GoogleReaderTimestamp.before(value: "1000000000000000", now: 500) == 1_000_000_000)
        #expect(try GoogleReaderTimestamp.before(value: "1000000000", now: 500) == 1_000_000_000)
        #expect(try GoogleReaderTimestamp.before(value: "+1000000000000000", now: 500) == 1_000_000_000,
            "the plus is one of the characters the length counts")
        #expect(try GoogleReaderTimestamp.before(value: "+100000000000000", now: 500) == 100_000_000,
            "sixteen characters as read, fifteen digits of the parsed value")
    }

    @Test func thePositiveGuardLeavesTheDefaultForAnUnpositiveValue() async throws {
        #expect(try GoogleReaderTimestamp.before(value: "0", now: 500) == 500)
        #expect(try GoogleReaderTimestamp.before(value: "-1000000000", now: 500) == 500)
        #expect(try GoogleReaderTimestamp.before(value: "-1000000000000000", now: 500) == 500,
            "the sign guard runs before the length test")
    }

    @Test func theReadReportsTheValueItCannotParse() async throws {
        #expect(errorDescription(for: "x") == "strconv.ParseInt: parsing \"x\": invalid syntax")
        #expect(errorDescription(for: " 1") == "strconv.ParseInt: parsing \" 1\": invalid syntax",
            "the space is part of the value as read, which is what the wording names")
        #expect(errorDescription(for: "9223372036854775808") ==
            "strconv.ParseInt: parsing \"9223372036854775808\": value out of range")
    }

    @Test func theSubSecondPartIsNotWhatTheStorageReadCanShow() async throws {
        // 1_000_000_000_500_000 microseconds is 1_000_000_000.5 seconds; the entry column holds
        // whole seconds, so the answer is the whole part.
        #expect(try GoogleReaderTimestamp.before(value: "1000000000500000", now: 500) == 1_000_000_000)
    }

    private func errorDescription(for value: String) -> String {
        do {
            _ = try GoogleReaderTimestamp.before(value: value, now: 500)
            return "no error"
        } catch {
            return String(describing: error)
        }
    }
}
