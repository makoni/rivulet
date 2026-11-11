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
/// than being written as the strong form; that the value is trimmed before the shape is decided, so
/// the spaces are not part of the quoted form; that an empty value answers the empty string, which
/// is what the reference's early return gives and not a quoted empty tag; that the match read
/// answers false when either side is empty; that the star answers true for any tag; that the
/// comparison is weak — the prefix is not part of the tag compared, so the weak form on either side
/// reaches the strong one; that a header listing several tags is read as containing the tag rather
/// than as being equal to it; that `Cache-Control` is built from the whole seconds of the bound,
/// truncated and not rounded, which a patch that rounded the value fails on; that the directives
/// are written in the order the builder writes them, with `max-age` before `immutable`; and that
/// `Expires` is the instant the rule is given, written in the shape and in the zone the reference
/// writes it in.
///
/// Each rule is read by one patch, with two arrangements the round records. Two pins name two rules
/// of one read each — the match read's prefix drop with its contains read, and `Cache-Control`'s
/// whole seconds with its directive order — so each of those pins is read by one patch per rule
/// rather than by one patch in total. And the pin that names the trim reads an already quoted value
/// with spaces, which the patch for the quoted half reaches as well: the pin that names the quoted
/// half is read only by its own patch, because its value has no spaces, and the trim patch reaches
/// only the pin whose value has them.
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

    @Test func theValueIsTrimmedBeforeItsShapeIsDecided() throws {
        // The input carries spaces on both sides of an already quoted value, so the shape is
        // decided on the trimmed value and the spaces are not part of it. The pin reads the trim
        // alone: a patch that decided on the value as it was read answered `""abc""` here, and a
        // patch that trimmed after the shape answered `"  "abc"  "`. It is not read by the patch
        // that names the quoted half, which answers `""abc""` and reaches the pin that names that
        // half as well.
        #expect(CachingRules.etag("  \"abc\"  ") == "\"abc\"", "the trim runs before the shape")
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
        // `*` is read as the wildcard, not as a tag: it is compared as the value the trim gives.
        #expect(CachingRules.matchesNoneMatch(headerValue: " * ", etag: "\"abc\""),
            "the star matches any tag")
    }

    @Test func theMatchReadDropsThePrefixAndReadsTheHeaderAsContainingTheTag() throws {
        // Two rules the same read applies, pinned as one pin because a patch to either reaches it
        // and no other pin reads either: the weak prefix is dropped from the tag before the
        // comparison, so the weak form reaches the strong one, and the header is read as containing
        // the tag rather than as being equal to it. A patch that compared the whole etag answered
        // false for the first input; a patch that compared the header as one value answered false
        // for the second, and a patch that read any part of the tag answered true for the third.
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
        // The shape is `http.TimeFormat` and the zone is UTC. The two inputs read three rules: the
        // bound added to the instant, the three-letter weekday, and the padded day field — a day of
        // 4 answers `04`, which is why the field is not the number. A patch that wrote the value
        // with the machine's local zone answered `Sun, 04 Jan 2026 21:20:03 GMT` for the second
        // input: this machine is `+07:00`, which is where the probe for that rule fires, while on a
        // UTC machine the two answers are the same, so that half is named in the header rather than
        // pinned here. The instant itself is what the run reads from the clock, so no pin can name
        // it.
        let instant = Date(timeIntervalSince1970: 1_767_550_803) // Sun, 04 Jan 2026 18:20:03 UTC
        #expect(CachingRules.expires(now: instant, duration: 259_200) ==
            "Wed, 07 Jan 2026 18:20:03 GMT", "the bound is added to the instant given")
        #expect(CachingRules.expires(now: instant, duration: 1) ==
            "Sun, 04 Jan 2026 18:20:04 GMT", "the weekday and the day fields are the shape they are")
    }
}
