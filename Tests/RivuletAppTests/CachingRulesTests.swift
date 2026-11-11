import Foundation
import Testing
@testable import RivuletApp

/// The caching rules the reference's response builder applies for a cached asset
/// (`internal/http/response/builder.go` at `c4d54f87`): the ETag shape, the `If-None-Match` read,
/// the `Cache-Control` value and the `Expires` value. The route that answers an icon runs these
/// rules; `IconRouteTests` pins what the route adds on top of them, and this file pins the rules
/// themselves.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the quoted
/// shape is added for a value that carries no quotes, which a patch that wrote the value as it was
/// given fails on; that a value already carrying the quoted form is written as it was read, which a
/// patch that quoted it a second time fails on; that the weak form keeps its `W/` prefix rather
/// than being written as the strong form; that the value is trimmed before the shape is decided,
/// with the class the reference trims with — Unicode `White_Space`, which is wider than Swift's
/// `.whitespaces` — so the pin's input carries a newline; that an empty value answers the empty
/// string, which is what the reference's early return gives and not a quoted empty tag; that the
/// match read answers false when either side is empty; that the star answers true for any tag and
/// that the value it is compared with is the trimmed one; that the comparison is weak — the prefix
/// is not part of the tag compared, so the weak form on either side reaches the strong one — and
/// that a header listing several tags is read as containing the tag rather than as being equal to
/// it; that `Cache-Control` is built from the whole seconds of the bound, truncated and not
/// rounded, which a patch that rounded the value fails on; that the directives are written in the
/// order the builder writes them, with `max-age` before `immutable`; and that `Expires` is the
/// instant the rule is given with the whole bound added, written in the shape and in the zone the
/// reference writes it in.
///
/// Five pins here are read by more than one patch, one patch per rule they name, which is what the
/// round expects for those rows: the trim pin (its patch for the order, its patch for the class,
/// and the reach from the quoted-half patch, whose input is already quoted), the star pin (the star
/// patch and the trim patch), the match pin (the prefix drop, the contains read, the whole-tag
/// read), the `Cache-Control` pin (whole seconds, directive order) and the `Expires` pin (the
/// bound, the zone, the weekday, the day field). The other five pins are read by one patch each.
///
/// What these pins cannot fail on: the instant the run is at, which is a clock read the route makes
/// and no test can name, so the pins read the rule with the instant handed to it; the zone rule,
/// which can be shown only on a machine whose local zone is not UTC — this machine is `+07:00`, so
/// that probe fires here and not on a UTC runner; the fixed locale the shape is written with, which
/// cannot be shown on a machine already reading English weekday and month names; the compression
/// the reference skips for a body that is not SVG, which this port has no middleware for, so no
/// patch here can show it; and the `Vary` header the reference writes only above its compression
/// threshold, which no response of this path reaches; and the guard that an empty side answers
/// false, which cannot be shown by taking the guard away — an empty value is inside every value for
/// Go's `strings.Contains`, which is the other half of that rule, while Swift's read answers false
/// for an empty value, so this pin is shown to fail by a patch that flips the answer the guard
/// gives. The difference is recorded in `docs/parity.md`.
@Suite struct CachingRulesTests {
    @Test func theQuotedShapeIsAddedForAValueThatCarriesNoQuotes() throws {
        // The reference writes the value as it was read only when it already carries a quote or the
        // weak prefix, so the hash a storage read answers is quoted here.
        #expect(CachingRules.etag("71e9d7c8fd7d2b3dc94c3de389826bd8") ==
            "\"71e9d7c8fd7d2b3dc94c3de389826bd8\"", "the shape is added")
    }

    @Test func anETagThatAlreadyCarriesTheQuotedFormIsWrittenAsItWasRead() throws {
        // A patch that quoted whatever it was given wrote `""abc""` for this input and passed the
        // pin that names the added shape.
        #expect(CachingRules.etag("\"abc\"") == "\"abc\"", "the value is not quoted a second time")
    }

    @Test func theWeakFormKeepsItsPrefix() throws {
        // A patch that wrote the weak form as the strong one answered `"abc"` here. The prefix is
        // what this pin reads, and it is the part the match read drops, which the pin that names
        // the comparison reads from the other side.
        #expect(CachingRules.etag("W/\"abc\"") == "W/\"abc\"", "the prefix is part of the value")
    }

    @Test func theValueIsTrimmedWithTheReferenceClassBeforeItsShapeIsDecided() throws {
        // Two halves of one rule, read by two patches. The order: the shape is decided on the
        // trimmed value, so a patch that took the trim away answered the value as it was read. The
        // class: Unicode `White_Space`, which is wider than Swift's `.whitespaces`, so the input
        // carries a newline — a patch that used the narrower class kept it inside the quoted form.
        // This pin is also read by the patch that names the quoted half, because its value is
        // already quoted: that patch answers `""abc""` here, which is the pair the round records.
        #expect(CachingRules.etag("\n  \"abc\"  ") == "\"abc\"",
            "the class the trim reads and the order it runs in")
    }

    @Test func anEmptyETagAnswersTheEmptyStringAndNotAQuotedEmptyTag() throws {
        // The reference returns early for an empty value, so nothing is quoted and the match read
        // cannot reach the tag.
        #expect(CachingRules.etag("") == "", "the empty value is the empty answer")
    }

    @Test func theMatchReadAnswersFalseWhenEitherSideIsEmpty() throws {
        // The guard runs before the comparison, and the pin is shown to fail by a patch that flips
        // the answer the guard gives. It cannot be shown by taking the guard away: an empty value
        // is what Go's `strings.Contains` answers as inside every value, which is the other half of
        // the guard, while Swift's read answers false for an empty value, so removing the guard
        // changes nothing the pins can see here. That difference is recorded in `docs/parity.md`.
        #expect(!CachingRules.matchesNoneMatch(headerValue: "", etag: "\"abc\""),
            "a header with nothing in it is not a match")
        #expect(!CachingRules.matchesNoneMatch(headerValue: "\"abc\"", etag: ""),
            "and no header matches an empty tag")
    }

    @Test func theStarInIfNoneMatchMatchesAnyTag() throws {
        // Two rules of the same read, each read by its own patch: the star is read as the wildcard,
        // and the value it is compared with is the trimmed one — the input carries spaces, so a
        // patch that compared the header as it was read answered false here, and a patch that took
        // the trim away from this branch answered false for the same input.
        #expect(CachingRules.matchesNoneMatch(headerValue: " * ", etag: "\"abc\""),
            "the star matches any tag")
    }

    @Test func theMatchReadDropsThePrefixAndReadsTheHeaderAsContainingTheTag() throws {
        // One pin for the three rules this read applies, each with its own patch, and no other pin
        // reads any of the three. A patch that stopped dropping the prefix answered false for the
        // first input, which is what lets the weak form reach the strong one; a patch that compared
        // the header as one value answered false for the second; a patch that read any part of the
        // tag answered true for the third.
        #expect(CachingRules.matchesNoneMatch(headerValue: "\"abc\"", etag: "W/\"abc\""),
            "the weak etag reaches the strong header")
        #expect(CachingRules.matchesNoneMatch(headerValue: "\"xyz\", \"abc\"", etag: "\"abc\""),
            "the list still contains the tag")
        #expect(!CachingRules.matchesNoneMatch(headerValue: "\"ab\"", etag: "\"abc\""),
            "a part of the tag is not the tag")
    }

    @Test func cacheControlIsTheStringTheBuilderBuildsFromTheBound() throws {
        // Two rules of the same read, pinned as one pin because a patch to either reaches it and no
        // other pin reads either: `int64(duration.Seconds())` is whole seconds, read as `Int64`, so
        // the fraction is truncated — a patch that rounded answered 259231 for the first input —
        // and the directives are written in the order the reference puts them, `public`, then
        // `max-age`, then `immutable` — a patch that put `immutable` first answered the second
        // input with the order changed, and a patch that wrote `private` answered both inputs with
        // that word changed.
        #expect(CachingRules.cacheControl(259_230.7) == "public, max-age=259230, immutable",
            "the seconds as the reference counts them")
        #expect(CachingRules.cacheControl(259_200) == "public, max-age=259200, immutable",
            "the order the builder writes")
    }

    @Test func expiresIsTheInstantTheRuleIsGivenInTheShapeAndTheZoneTheReferenceWrites() throws {
        // The pin reads four rules of the formatter: the zone, the three-letter weekday, the padded
        // day field, and the bound added to the instant — added whole, since the reference
        // truncates only when it writes the value, so the whole-second counting is read where
        // `Cache-Control` is built, not here. The two inputs read the bound, the weekday and the
        // day: a day of 4 answers `04`, which is why the field is not the number. The zone is read
        // through the formatter's zone, with its own patch: on this machine, whose zone is
        // `+07:00`, a patch that wrote the value with the machine's local zone answered `Thu, 08
        // Jan 2026 01:20:03 GMT` for the first input, while on a UTC runner the two answers are the
        // same, so the zone rule can be shown here and not there. The instant itself is what the
        // run reads from the clock, so no pin can name it.
        let instant = Date(timeIntervalSince1970: 1_767_550_803) // Sun, 04 Jan 2026 18:20:03 UTC
        #expect(CachingRules.expires(now: instant, duration: 259_200) ==
            "Wed, 07 Jan 2026 18:20:03 GMT", "the bound is added to the instant given")
        #expect(CachingRules.expires(now: instant, duration: 1) ==
            "Sun, 04 Jan 2026 18:20:04 GMT", "the weekday and the day fields are the shape they are")
    }
}
