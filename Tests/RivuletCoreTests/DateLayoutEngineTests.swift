import Foundation
import Testing
@testable import RivuletCore

/// The layout engine, which is Go's `time.parse` over one layout (Go 1.22 `time/format.go`).
///
/// Each test gives the engine one layout and one value, so what it pins is the engine's own rule,
/// not which layout the catalog tries first; the catalog order is pinned in `DateParserTests`. The
/// values are derived from the reference semantics, computed as wall time and then moved by the
/// resolved zone offset.
///
/// What this engine cannot do is recorded in `docs/parity.md`: the machine's local zone is never
/// consulted, so an abbreviation resolves through the fixed table, and the name reported is the
/// name as read. A value that reads no zone is read as UTC here, which is also what Go's `Parse`
/// does, so the pins that carry no zone hold on any machine.
@Suite struct DateLayoutEngineTests {
    // MARK: - Literal text between chunks (`skip`)

    @Test func layoutSpaceMatchesARunOfSpacesInTheValue() throws {
        let parsed = try #require(
            DateLayoutEngine.parse(layout: "Mon, 02 Jan 2006 15:04:05 MST",
                value: "Tue,  25 Feb 2016 00:00:00 CET")
        )
        #expect(parsed.epochSeconds == 1456358400)
    }

    @Test func aLayoutSpaceNeedsASpaceInTheValue() {
        #expect(DateLayoutEngine.parse(layout: "Mon, 02 Jan 2006 15:04:05 MST",
            value: "Tue, 25 Feb 2016 00:00:00CET") == nil)
    }

    @Test func literalTextBetweenChunksMustMatchExactly() {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02", value: "2016/02/04") == nil)
    }

    @Test func textLeftOverAfterTheLayoutIsNotConsumed() {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02", value: "2016-02-04 extra") == nil)
    }

    // MARK: - Name chunks (`lookup`)

    @Test func nameLookupIgnoresCase() throws {
        let parsed = try #require(
            DateLayoutEngine.parse(layout: "Mon, 02 Jan 2006 15:04:05 MST",
                value: "tue, 25 feb 2016 00:00:00 CET")
        )
        #expect(parsed.epochSeconds == 1456358400)
    }

    @Test func aNameChunkConsumesOnlyItsOwnLength() throws {
        // `lookup` matches a prefix of the value, so "Feb" is consumed here and the digits that
        // follow go on to the year chunk. A whole-word match would have failed this value.
        let parsed = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan06 MST",
            value: "Tue, 25 Feb20 CET"))
        #expect(parsed.epochSeconds == 1582588800)
        #expect(parsed.zoneName == "CET")
    }

    // MARK: - Numeric fields (`getnum`, `getnum3`, `atoi`)

    @Test func aFixedFieldNeedsItsTwoDigits() {
        #expect(DateLayoutEngine.parse(layout: "Mon, 02 Jan 2006", value: "Tue, 4 Feb 2016") == nil)
    }

    @Test func anUnpaddedFieldAcceptsOneDigit() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan 2006",
            value: "Tue, 4 Feb 2016"))
        #expect(parsed.epochSeconds == 1454544000)
    }

    @Test func twoDigitYearRuleSplitsAtSixtyNine() throws {
        let asNineteen = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan 06",
            value: "Tue, 4 Feb 71"))
        let asTwoThousand = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan 06",
            value: "Tue, 4 Feb 68"))
        #expect(asNineteen.epochSeconds == 34473600)
        #expect(asTwoThousand.epochSeconds == 3095539200)
    }

    @Test func aTwoDigitYearReadsASignBecauseGoUsesAtoiThere() throws {
        // `stdYear` takes two characters and hands them to `atoi`, which accepts a leading sign, so
        // `+6` is 2006 and `-6` is 1994. The four-digit year checks a digit at position zero first,
        // so a sign there fails, and `getnum` takes digits only.
        let plus = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan 06", value: "Tue, 4 Feb +6"))
        let minus = try #require(DateLayoutEngine.parse(layout: "Mon, 2 Jan 06", value: "Tue, 4 Feb -6"))
        #expect(plus.epochSeconds == 1139011200)
        #expect(minus.epochSeconds == 760320000)
        #expect(DateLayoutEngine.parse(layout: "Mon, 2 Jan 2006", value: "Tue, 4 Feb -016") == nil)
    }

    @Test func hourOverTwentyFourFails() {
        #expect(DateLayoutEngine.parse(layout: "15:04", value: "24:00") == nil)
    }

    @Test func twelveHourOverTwelveFails() {
        #expect(DateLayoutEngine.parse(layout: "3:04", value: "13:04") == nil)
    }

    @Test func minuteOverSixtyFails() {
        #expect(DateLayoutEngine.parse(layout: "15:04", value: "21:60") == nil)
    }

    @Test func dayMustFitTheMonth() throws {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02", value: "2015-02-29") == nil)
        let leapDay = try #require(DateLayoutEngine.parse(layout: "2006-01-02", value: "2016-02-29"))
        #expect(leapDay.epochSeconds == 1456704000)
    }

    @Test func monthOutOfRangeFails() {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02", value: "2016-13-02") == nil)
    }

    @Test func yearDayOutOfRangeFails() {
        #expect(DateLayoutEngine.parse(layout: "2006-002", value: "2016-000") == nil)
        #expect(DateLayoutEngine.parse(layout: "2006-002", value: "2015-366") == nil)
    }

    @Test func yearDayIsConvertedThroughTheLeapYearRule() throws {
        // Day 60 is February 29 in a leap year and March 1 in a common one; a leap year also lets
        // day 366 stand, because the reference decrements the year-day past February before
        // matching it against the common-year table.
        let leapYearDay = try #require(DateLayoutEngine.parse(layout: "2006-002", value: "2016-060"))
        let commonYearDay = try #require(DateLayoutEngine.parse(layout: "2006-002", value: "2015-060"))
        let leapYearLastDay = try #require(DateLayoutEngine.parse(layout: "2006-002", value: "2016-366"))
        #expect(leapYearDay.epochSeconds == 1456704000)
        #expect(commonYearDay.epochSeconds == 1425168000)
        #expect(leapYearLastDay.epochSeconds == 1483142400)
    }

    @Test func yearDayMustAgreeWithMonthAndDay() throws {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 002", value: "2016-02-04 036") == nil)
        let matching = try #require(DateLayoutEngine.parse(layout: "2006-01-02 002",
            value: "2016-02-05 036"))
        #expect(matching.epochSeconds == 1454630400)
    }

    // MARK: - AM/PM

    @Test func pmShiftsAnHourBelowTwelve() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 3:04PM",
            value: "2016-02-04 1:04PM"))
        #expect(parsed.epochSeconds == 1454591040)
    }

    @Test func pmKeepsTwelveAndAmTurnsTwelveIntoMidnight() throws {
        let noon = try #require(DateLayoutEngine.parse(layout: "2006-01-02 3:04PM",
            value: "2016-02-04 12:04PM"))
        let midnight = try #require(DateLayoutEngine.parse(layout: "2006-01-02 3:04pm",
            value: "2016-02-04 12:04am"))
        #expect(noon.epochSeconds == 1454587440)
        #expect(midnight.epochSeconds == 1454544240)
    }

    // MARK: - Zone names (`parseTimeZone`, `parseGMT`, `parseSignedOffset`)

    @Test func threeUpperLettersAreAZoneName() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 CET"))
        #expect(parsed.zoneName == "CET")
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    @Test func fourLettersNeedTWithTheDocumentedExceptions() throws {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 ABCA") == nil)
        let exception = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 WITA"))
        #expect(exception.zoneName == "WITA")
    }

    @Test func fiveLettersNeedT() throws {
        let matching = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 ABCDT"))
        #expect(matching.zoneName == "ABCDT")
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 ABCDE") == nil)
    }

    @Test func sixUpperLettersAndLowercaseNamesAreNotZones() {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 ABCDEF") == nil)
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 Cet") == nil)
    }

    @Test func bareUTIsNotAZoneEvenThoughGoDocumentsItAsOne() {
        // Go's documentation lists `UT` among the names it recognizes, but `parseTimeZone` only
        // special-cases `GMT` and `UTC`, so a two-letter `UT` never reaches the three-letter
        // branch.
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 UT") == nil)
    }

    @Test func gmtHourOffsetStaysInNameAndBecomesTheOffset() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 GMT+03"))
        #expect(parsed.zoneName == "GMT+03")
        #expect(parsed.zoneOffsetSeconds == 10800)
        #expect(parsed.epochSeconds == 1454608857)
    }

    @Test func aShortSignedOffsetBecomesANameAndKeepsZeroOffset() throws {
        // `parseSignedOffset` accepts `+01` as a zone here, and the table has no entry for it, so
        // Go's documented fallback applies: the name is kept and the offset stays zero.
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 +01"))
        #expect(parsed.zoneName == "+01")
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    @Test func aThreeDigitNumberIsNotAZoneName() {
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 +0100") == nil)
    }

    @Test func tableNamesResolveThroughTheFixedTable() throws {
        // The four names in the table are the ones the reference's workaround locations pin, and
        // the table holds their fixed offsets, so a winter value still gets the daylight-saving
        // offset for `PDT`. The reference would have asked the machine's local zone instead.
        let pacific = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 PDT"))
        let eastern = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 MST",
            value: "2016-02-04 21:00:57 EDT"))
        #expect(pacific.zoneOffsetSeconds == -25200)
        #expect(eastern.zoneOffsetSeconds == -14400)
    }

    @Test func numericOffsetKeepsTheNameAsParsedWhichIsEmpty() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02T15:04:05Z07:00",
            value: "2016-02-04T21:00:57+02:00"))
        #expect(parsed.zoneName == "")
        #expect(parsed.zoneOffsetSeconds == 7200)
        #expect(parsed.epochSeconds == 1454612457)
    }

    @Test func isoZIsReadAsUtcAndAnUnpaddedFieldIsAcceptedByTheGeneralPath() throws {
        // The first pair is Go's `RFC3339` constant, where `Parse` takes the fast path; on this
        // value the fast path and the general `parse` agree. The second pair is not the constant,
        // so only the general path runs there, and it accepts an unpadded field. Both read a
        // literal `Z` as UTC.
        let fixed = try #require(DateLayoutEngine.parse(layout: "2006-01-02T15:04:05Z07:00",
            value: "2016-02-04T21:00:57Z"))
        let unpadded = try #require(DateLayoutEngine.parse(layout: "2006-1-2T15:04:05Z",
            value: "2016-2-4T21:00:57Z"))
        #expect(fixed.zoneName == "UTC")
        #expect(unpadded.epochSeconds == 1454619657)
    }

    @Test func theEngineDoesNotClampAnOutOfRangeOffset() throws {
        // `checkTimezoneRange` belongs to the entry point, which is where the clamp to UTC happens,
        // so the engine reports what the layout read.
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02T15:04:05Z07:00",
            value: "2016-02-04T21:00:57-13:00"))
        #expect(parsed.zoneOffsetSeconds == -46800)
        #expect(parsed.epochSeconds == 1454666457)
    }

    @Test func aLayoutWithoutAZoneFallsBackToTheDefaultWhichIsUtc() throws {
        // Go's `Parse` uses UTC as its default location too, so this is reference parity rather
        // than a deviation, and the pin holds on any machine.
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05",
            value: "2016-02-04 21:00:57"))
        #expect(parsed.zoneName == "UTC")
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    @Test func anOffsetOfExactlyOneSecondIsGoSentinelForNoOffsetRead() throws {
        // Go keeps `zoneOffset = -1` to mean "no offset was read", so a value of exactly −1 second
        // is read as no offset at all: the instant stays the wall time and the zone is the default
        // one, which for this port is UTC.
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05 -07:00:00",
            value: "2016-02-04 21:00:57 -00:00:01"))
        #expect(parsed.epochSeconds == 1454619657)
        #expect(parsed.zoneOffsetSeconds == 0)
        #expect(parsed.zoneName == "UTC")
    }

    // MARK: - Fractional seconds (`parseNanoseconds`)

    @Test func fractionalSecondParsesEvenWhenTheLayoutHasNoFraction() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05",
            value: "2016-02-04 21:00:57.0123"))
        // The whole run of digits is taken, then scaled by the missing digits, which is 123 * 10^5.
        #expect(parsed.nanoseconds == 12_300_000)
        #expect(parsed.epochSeconds == 1454619657)
    }

    @Test func anExactFractionalChunkTakesItsOwnDigitsOnly() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.000",
            value: "2016-02-04 21:00:57.012"))
        #expect(parsed.nanoseconds == 12_000_000)
        // One digit more than the layout asks for is left over, and leftover text is a failure.
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.000",
            value: "2016-02-04 21:00:57.0123") == nil)
    }

    @Test func aSignInsideAnExactFractionalRunIsReadByAtoi() throws {
        // `stdFracSecond0` does not check that the characters after the separator are digits: it
        // hands what it took to `atoi`, which accepts a leading `+`. A negative result is out of
        // range, so the same shape with `-` is not a match.
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.00",
            value: "2016-02-04 21:00:57.+5"))
        #expect(parsed.nanoseconds == 50_000_000)
        #expect(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.00",
            value: "2016-02-04 21:00:57.-5") == nil)
    }

    @Test func aNineFractionalChunkTakesEveryDigitUpToTen() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.999",
            value: "2016-02-04 21:00:57.123456789012"))
        #expect(parsed.nanoseconds == 123_456_789)
    }

    @Test func aNineFractionalChunkAllowsTheFractionToBeOmitted() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05.999",
            value: "2016-02-04 21:00:57"))
        #expect(parsed.nanoseconds == 0)
    }

    @Test func aCommaIsAcceptedAsTheFractionSeparator() throws {
        let parsed = try #require(DateLayoutEngine.parse(layout: "2006-01-02 15:04:05,999",
            value: "2016-02-04 21:00:57,123"))
        #expect(parsed.nanoseconds == 123_000_000)
    }
}
