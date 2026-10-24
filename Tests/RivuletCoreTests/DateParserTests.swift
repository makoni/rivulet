import Foundation
import Testing
@testable import RivuletCore

/// Date parsing. Ported from Miniflux `internal/reader/date/parser.go`; the tests that mirror an
/// upstream assertion name the upstream test (`parser_test.go`).
///
/// The order is the reference's: an integer Unix timestamp wins over every layout, then the three
/// local-time layouts, then the 206 layouts listed after normalization. The offset clamp to UTC for
/// values outside −12:00 to +14:00 is the reference's. Abbreviations are read through a fixed table
/// rather than the machine's local zone, which is the deviation recorded in `docs/parity.md`: the
/// four names the reference works around (PST/PDT and EST/EDT, through Los Angeles and New York)
/// keep the offsets those locations read at the instants the ported tests use, and everything else
/// gets the documented fallback of 0. A value that reads no zone is read as UTC here, as it is by
/// Go's `Parse`.
@Suite struct DateParserTests {
    // MARK: - Ported upstream cases

    /// `TestParseEmptyDate`
    @Test func emptyInputFails() {
        #expect(throws: DateParseError.empty) { try FeedDateParser.parse("  ") }
    }

    /// `TestParseInvalidDate`
    @Test func invalidInputFails() {
        #expect(throws: DateParseError.failedToParse(input: "invalid")) { try FeedDateParser.parse("invalid") }
    }

    /// `TestParseAtomDate`
    @Test func atomDateWithZeroOffsetParsesToItsInstant() throws {
        let parsed = try FeedDateParser.parse("2017-12-22T22:09:49+00:00")
        #expect(parsed.epochSeconds == 1513980589)
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    /// `TestParseRSSDateTimezone`. The reference reaches this instant through tzdata, so it depends
    /// on the machine; the pin is the instant upstream asserts, which the port reaches through its
    /// fixed table. The name is reported as read, not as the IANA location.
    @Test func ianaZoneNameIsNormalizedToItsAbbreviationAndKeepsItsOffset() throws {
        let parsed = try FeedDateParser.parse("Fri, 31 Mar 2023 20:19:00 America/Los_Angeles")
        #expect(parsed.epochSeconds == 1680319140)
        #expect(parsed.zoneName == "PDT")
        #expect(parsed.zoneOffsetSeconds == -25200)
    }

    /// `TestParseRSSDateGMT`
    @Test func gmtKeepsItsNameAndZeroOffset() throws {
        let parsed = try FeedDateParser.parse("Tue, 03 Jun 2003 09:39:21 GMT")
        #expect(parsed.epochSeconds == 1054633161)
        #expect(parsed.zoneName == "GMT")
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    /// `TestParseRSSDatePST`
    @Test func pacificStandardTimeUsesTheWorkaroundOffset() throws {
        let parsed = try FeedDateParser.parse("Wed, 26 Dec 2018 10:00:54 PST")
        #expect(parsed.epochSeconds == 1545847254)
        #expect(parsed.zoneName == "PST")
        #expect(parsed.zoneOffsetSeconds == -28800)
    }

    /// `TestParseRSSDateEST`
    @Test func easternStandardTimeUsesTheWorkaroundOffset() throws {
        let parsed = try FeedDateParser.parse("Wed, 10 Feb 2021 22:46:00 EST")
        #expect(parsed.epochSeconds == 1613015160)
        #expect(parsed.zoneName == "EST")
        #expect(parsed.zoneOffsetSeconds == -18000)
    }

    /// `TestParseRSSDateOffset`
    @Test func numericOffsetIsUsedAsWritten() throws {
        let parsed = try FeedDateParser.parse("Sun, 28 Oct 2018 13:48:00 +0100")
        #expect(parsed.epochSeconds == 1540730880)
        #expect(parsed.zoneOffsetSeconds == 3600)
    }

    /// `TestParseWeirdDateFormat`
    @Test func theUpstreamCorpusStillParses() throws {
        let inputs = [
            "Sun, 17 Dec 2017 1:55 PM EST",
            "9 Dec 2016 12:00 GMT",
            "Friday, December 22, 2017 - 3:09pm",
            "Friday, December 8, 2017 - 3:07pm",
            "Thu, 25 Feb 2016 00:00:00 Europe/Brussels",
            "Mon, 09 Apr 2018, 16:04",
            "Di, 23 Jan 2018 00:00:00 +0100",
            "Do, 29 Mär 2018 00:00:00 +0200",
            "mer, 9 avr 2018 00:00:00 +0200",
            "1520932969",
            "Tue 16 Feb 2016, 23:16:00 EDT",
            "Tue, 16 Feb 2016 23:16:00 EDT",
            "Tue, Feb 16 2016 23:16:00 EDT",
            "March 30 2020 07:02:38 PM",
            "Mon, 30 Mar 2020 19:53 +0000",
            "Mon, 03/30/2020 - 19:19",
            "2018-12-12T12:12",
            "2020-11-08T16:20:00-05:00Z",
            "Nov. 16, 2020, 10:57 a.m.",
            "Friday 06 November 2020",
            "Mon, November 16, 2020, 11:12 PM EST",
            "Lundi, 16. Novembre 2020 - 15:54",
            "Thu Nov 12 2020 17:00:00 GMT+0000 (Coordinated Universal Time)",
            "Sat, 11 04 2020 08:51:49 +0100",
            "Mon, 16th Nov 2020 13:16:28 GMT",
            "Nov. 2020",
            "ven., 03 juil. 2020 15:09:58 +0000",
            "Fri, 26/06/2020",
            "Thu, 29 Oct 2020 07:36:03 GMT-07:00",
            "jeu., 02 avril 2020 00:00:00 +0200",
            "Jan. 4, 2016, 12:37 p.m.",
            "2018-10-23 04:07:42 +00:00",
            "5 August, 2019",
            "mar., 01 déc. 2020 16:11:02 +0000",
            "Thurs, 15 Oct 2020 00:00:39 +0000",
            "Thur, 19 Nov 2020 00:00:39 +0000",
            "26 Sep 2022 GMT",
            "Thu, June 22, 2023 at 01:11 PM EDT",
            "Apr 16, 2023 08:01 GMT",
            "Jun 23, 2023 19:00 GMT",
            "09/15/2014 4:20 pm PST",
            "Fri, 23rd Jun 2023 09:32:20 GMT",
            "Sat, Oct 28 2023 08:28:28 PM",
            "Monday, October 6, 2023 - 16:29\n",
            "10/30/23 21:55:58",
            "30.10.23",
        ]

        for input in inputs {
            #expect(throws: Never.self) { try FeedDateParser.parse(input) }
        }
    }

    /// `TestParseDateWithTimezoneOutOfRange`
    @Test func offsetsOutsideTheRangeAreClampedToUtc() throws {
        for input in ["2023-05-29 00:00:00-13:00", "2023-05-29 00:00:00+15:00"] {
            let parsed = try FeedDateParser.parse(input)
            #expect(parsed.zoneName == "UTC")
            #expect(parsed.zoneOffsetSeconds == 0)
        }
    }

    // MARK: - Pins for values the upstream corpus does not assert

    @Test func integerTimestampWinsOverTheLayouts() throws {
        let parsed = try FeedDateParser.parse("1520932969")
        #expect(parsed.epochSeconds == 1520932969)
        #expect(parsed.nanoseconds == 0)
    }

    @Test func normalizedGermanDayKeepsItsInstantAndOffset() throws {
        // "Di," becomes "Tue," and the layout with a numeric offset is the one that matches, so the
        // instant is the wall time moved by the offset.
        let parsed = try FeedDateParser.parse("Di, 23 Jan 2018 00:00:00 +0100")
        #expect(parsed.epochSeconds == 1516662000)
        #expect(parsed.zoneOffsetSeconds == 3600)
    }

    @Test func normalizedGermanMonthKeepsItsInstantAndOffset() throws {
        let parsed = try FeedDateParser.parse("Do, 29 Mär 2018 00:00:00 +0200")
        #expect(parsed.epochSeconds == 1522274400)
        #expect(parsed.zoneOffsetSeconds == 7200)
    }

    @Test func normalizedFrenchMonthKeepsItsInstantAndOffset() throws {
        // "9" is one digit, so the layout that fixes the day to two digits cannot match this one.
        let parsed = try FeedDateParser.parse("mer, 9 avr 2018 00:00:00 +0200")
        #expect(parsed.epochSeconds == 1523224800)
        #expect(parsed.zoneOffsetSeconds == 7200)
    }

    @Test func abbreviationOutsideTheTableKeepsZeroOffset() throws {
        // The reference resolves an abbreviation the machine's local zone does not know as a zero
        // offset; the port always does, which is what makes the suite deterministic.
        let parsed = try FeedDateParser.parse("Thu, 25 Feb 2016 00:00:00 CET")
        #expect(parsed.epochSeconds == 1456358400)
        #expect(parsed.zoneName == "CET")
        #expect(parsed.zoneOffsetSeconds == 0)
    }

    @Test func gmtHourOffsetStaysInNameWhenTheSignFollowsItImmediately() throws {
        // `parseGMT` takes the whole "GMT+03" as the name and turns the number into the offset,
        // because the replacer only spaces out `GMT-`, not `GMT+`. The local-time group wins here.
        let parsed = try FeedDateParser.parse("Thu, 29 Oct 2020 07:36:03 GMT+03")
        #expect(parsed.zoneName == "GMT+03")
        #expect(parsed.zoneOffsetSeconds == 10800)
        #expect(parsed.epochSeconds == 1603946163)
    }

    @Test func spacedGmtKeepsItsNameAndTheOffsetComesFromTheLayout() throws {
        // The reference's replacer turns `GMT-` into `GMT -`, so `parseGMT` stops at `GMT` and the
        // numeric offset is read by the layout that has both a name and an offset: name `GMT`,
        // offset −07:00. A `GMT-7` name would only appear when the sign follows immediately.
        let parsed = try FeedDateParser.parse("Thu, 29 Oct 2020 07:36:03 GMT-07:00")
        #expect(parsed.zoneName == "GMT")
        #expect(parsed.zoneOffsetSeconds == -25200)
        #expect(parsed.epochSeconds == 1603982163)
    }

    @Test func twoDigitYearFollowsTheReferenceRule() throws {
        // Go: NN >= 69 is 19NN, otherwise 20NN. The winning layout here is one of the general list,
        // so the name is read as parsed and the offset comes from the port's fixed table, where EST
        // is −18000; the reference asks the machine's local zone for this input, because its New
        // York workaround only covers the three local-time layouts.
        let parsed = try FeedDateParser.parse("Thu, 04 Feb 71 21:00:57 EST")
        #expect(parsed.epochSeconds == 34567257)
        #expect(parsed.zoneName == "EST")
        #expect(parsed.zoneOffsetSeconds == -18000)
    }

    @Test func twoDigitYearWithANumericOffsetIsReadTheSameWay() throws {
        // The same wall time, but with the offset written as a number, so the pin does not depend
        // on the zone table at all: 1971-02-04 21:00:57 is 34549257 seconds from the epoch as wall
        // time, and −07:00 moves the instant by 25200.
        let parsed = try FeedDateParser.parse("Thu, 04 Feb 71 21:00:57 -0700")
        #expect(parsed.epochSeconds == 34574457)
        #expect(parsed.zoneOffsetSeconds == -25200)
    }

    // MARK: - Normalization (`replacer`)

    @Test func theFirstPairAtAPositionWins() {
        // Go gives each pair a priority by its position in the table, so `Mai ` wins over `Mai`
        // where both match at a position, and `Mai` is the pattern that is a prefix of `Mai `. The
        // two write the same word with the same trailing space, so this decides only how far the
        // scan advances, and the output is the same under either rule.
        #expect(DateInputNormalizer.normalized("5 Mai 2016") == "5 May 2016")
    }

    @Test func theScanAdvancesByThePatternLength() {
        // The scan continues after the pattern, not after the replacement, so the second pair is
        // matched from the text after `nov.` and its own replacement is never rescanned.
        #expect(DateInputNormalizer.normalized("nov.november x") == "NovemberNovemberx")
    }
}
