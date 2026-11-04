import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The stream filter the Google Reader router builds — `parseStreamFilterFromRequest`
/// (`internal/googlereader/request_modifier.go` at `c4d54f87`) and the parameter names it reads
/// (`internal/googlereader/parameters.go`). The goldens are the reference's own output for these
/// queries at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the four names the
/// filter reads, which a patch that swapped two of them fails — `s`, `xt` and `it` answer three
/// different lists; the order read's default, which a patch that read the default as `o` fails, and
/// that only the single lowercase letter `o` is ascending, which a patch that compared the value
/// case-insensitively fails on `r=O`; that the value is compared as the pair read gives it, which a
/// patch that trimmed it first fails on `r=%20o`; the list read's trim and its skip of an empty
/// value, which a patch that kept empty values or did not trim fails on the query it names in the
/// test: `?s=+feed/1&s=&s=%20feed/2&s=%09feed/3`, where the `+` is the space the pair read gives;
/// the integer read's three paths — empty, unparseable, negative — each answering the default,
/// which a patch that read only one of them fails, and `n=+50` shows that the number is parsed from
/// the value as the pair read gave it, so the space the `+` became is what makes it unparseable;
/// that the first value with a name is what a single read answers, which a patch that read the last
/// one fails; the order the three stream reads run in, which a patch that read the excludes before
/// the streams fails on the query that has a bad value in each list; the user id carried through to
/// the read; and the continuation rule, which is the sum only while it is below the total, so a
/// patch that answered it always fails on the page that is the whole answer.
///
/// What these pins cannot fail on: `WithOffset`'s branch that keeps only a positive offset, because
/// the parameter read already answers the default for a negative value, so no query reaches that
/// branch; the page-size clamp to `model.MaxEntryLimit`, which `EntryQueryTests` pins; that this
/// read uses the URL query rather than the merged form, so a POST body carrying `n` is not read
/// here, which is what the suite that sends the request shows; the sorting expression the storage
/// builder writes for the direction, which `EntryQueryTests` pins; `bitSize 0` for the int read,
/// which on this platform is 64 bits, so the two reads answer the same for the same value; and
/// which count the continuation rule is given, because that is the handler's choice and is pinned
/// with the handler.
@Suite struct GoogleReaderRequestModifiersTests {
    private let userID = 7

    private func filter(for query: String) throws -> GoogleReaderRequestModifiers {
        try GoogleReaderRequestModifiers(query: GoogleReaderQuery(query: query), userID: userID)
    }

    private func errorDescription(for query: String) -> String? {
        do {
            _ = try filter(for: query)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test func theThreeStreamListsAreReadFromTheirOwnNames() throws {
        let modifiers = try filter(for: "s=feed/1&xt=feed/2&it=feed/3")
        #expect(modifiers.streams.map(\.id) == ["1"], "the name the stream list is read from")
        #expect(modifiers.excludeTargets.map(\.id) == ["2"], "the name the excludes are read from")
        #expect(modifiers.filterTargets.map(\.id) == ["3"], "the name the filters are read from")

        // A name the query does not carry answers nothing, which is what the reference's map gives.
        let empty = try filter(for: "s=feed/1")
        #expect(empty.excludeTargets.isEmpty, "the excludes are read from their own name")
        #expect(empty.filterTargets.isEmpty, "and the filters from their own")
    }

    @Test func theOrderReadAnswersItsDefaultAndOnlyTheLowercaseOIsAscending() throws {
        #expect(try filter(for: "").sortDirection == "desc", "the default the read is given")
        #expect(try filter(for: "r=").sortDirection == "desc", "an empty value answers the default")
        #expect(try filter(for: "r=o").sortDirection == "asc", "the one value the reference compares")
        #expect(try filter(for: "r=O").sortDirection == "desc",
            "the comparison is case-sensitive, so the uppercase letter is not it")
        #expect(try filter(for: "r=x").sortDirection == "desc", "anything else keeps the default")

        // The value is compared as the pair read gives it, so the escape that puts a space in front
        // of the letter is not the value the reference compares. A patch that trimmed before
        // comparing answered ascending here.
        #expect(try filter(for: "r=%20o").sortDirection == "desc", "the value is compared as it is read")

        // `Get` answers the first value with the name, so the second `r` is not read.
        #expect(try filter(for: "r=x&r=o").sortDirection == "desc", "the first value with the name")
    }

    @Test func theListReadTrimsAndSkipsEmptyValues() throws {
        // The `+` is the space the pair read gives, so the trim is what makes each value a stream
        // id.
        let modifiers = try filter(for: "s=+feed/1&s=&s=%20feed/2&s=%09feed/3")
        #expect(modifiers.streams.map(\.id) == ["1", "2", "3"],
            "each value is trimmed before the stream read, and the empty one is not in the list")

        // The order the pairs came in is the order the list answers in.
        let ordered = try filter(for: "s=feed/2&s=feed/1")
        #expect(ordered.streams.map(\.id) == ["2", "1"], "the order the pairs came in")

        // A query that carries only empty values answers nothing, so the stream read's fallback
        // error is what a caller gets for `?s=`.
        #expect(try filter(for: "s=").streams.isEmpty, "an empty value is skipped before the read")
        #expect(errorDescription(for: "s=") == nil, "and nothing is read, so nothing is reported")
    }

    @Test func theIntegerReadAnswersTheDefaultForAnEmptyUnparseableOrNegativeValue() throws {
        let query = GoogleReaderQuery(query: "n=50&c=&r=abc&ot=-1&nt=9223372036854775808&p=%2B12")
        #expect(query.integer(named: "n", default: 7) == 50, "the value that parses is read")
        #expect(query.integer(named: "c", default: 7) == 7, "an empty value answers the default")
        #expect(query.integer(named: "r", default: 7) == 7, "a value that does not parse answers it")
        #expect(query.integer(named: "ot", default: 7) == 7, "a negative value answers it")

        // The reference's read is `bitSize 0`, which on this platform is 64 bits, so this value is
        // out of range for both reads and answers the default for both.
        #expect(query.integer64(named: "nt", default: 7) == 7, "a value above the integer limit")
        #expect(query.integer64(named: "ot", default: 7) == 7, "and the negative one for the 64-bit read")
        #expect(query.integer64(named: "n", default: 7) == 50, "the 64-bit read answers the same value")

        // The percent form is the character itself, so this value is a number with a sign, which
        // `strconv.ParseInt` reads: `n=%2B12` answers 12, while `n=+12` is the space the pair read
        // gave.
        #expect(query.integer(named: "p", default: 7) == 12, "the percent form of the sign is read")

        // `+50` is the pair read's space, so the number is not parseable: a patch that trimmed the
        // value before parsing it answered 50 here.
        let plus = GoogleReaderQuery(query: "n=+50")
        #expect(plus.value(named: "n") == " 50", "what the pair read answers for the plus form")
        #expect(plus.integer(named: "n", default: 7) == 7, "so the integer read answers the default")
    }

    @Test func theFilterCarriesTheValuesTheReferenceReadsForTheSameQuery() throws {
        let modifiers = try filter(for:
            "s=feed/1&s=feed/2&xt=user/-/state/com.google/starred&it=user/7/state/com.google/read" +
            "&n=50&c=5&r=o&ot=1700000000&nt=1800000000")
        #expect(modifiers.count == 50, "the page size as the read answers it")
        #expect(modifiers.offset == 5, "the continuation value as the read answers it")
        #expect(modifiers.sortDirection == "asc", "the order for `r=o`")
        #expect(modifiers.startTime == 1_700_000_000, "the start time")
        #expect(modifiers.stopTime == 1_800_000_000, "the stop time")
        #expect(modifiers.userID == userID, "the user the filter is read for")

        // A patch that read the page size as 1000 whenever the value was absent is what this fails
        // on: the read answers the default, and the clamp is a separate rule pinned by
        // `EntryQueryTests`.
        let defaults = try filter(for: "")
        #expect(defaults.count == 0, "the default the read is given, not the clamp")
        #expect(defaults.offset == 0, "and the default for the continuation parameter")
        #expect(defaults.sortDirection == "desc", "and the default for the order")
        #expect(defaults.startTime == 0, "the start time the reference reads as 0 when absent")
        #expect(defaults.stopTime == 0, "and the stop time")
    }

    @Test func theFirstStreamErrorIsTheReadThatRunsFirst() throws {
        // The reference reads the order, then the streams, then the excludes, then the filters, and
        // the first error ends the read. A patch that read the excludes before the streams reported
        // the other value here.
        #expect(errorDescription(for: "s=bogus&xt=bogus2") == "googlereader: unknown stream type: bogus",
            "the streams are read before the excludes")
        #expect(errorDescription(for: "xt=bogus2&it=bogus3") ==
            "googlereader: unknown stream type: bogus2", "then the excludes before the filters")
        #expect(errorDescription(for: "it=bogus3") ==
            "googlereader: unknown stream type: bogus3", "and the filters last")

        // The order read runs before any of them, so a query with only a bad order has no error.
        #expect(errorDescription(for: "r=x") == nil, "the order read answers nothing")
    }

    @Test func theContinuationIsAnsweredOnlyWhenMoreItemsRemain() throws {
        // `getItemRefsAndContinuation`: `count + offset` only while it is below the total,
        // otherwise 0, which is what the JSON shape leaves out.
        #expect(GoogleReaderRequestModifiers.continuation(returned: 2, offset: 0, total: 5) == 2,
            "the reference's output for a page with more items after it")
        #expect(GoogleReaderRequestModifiers.continuation(returned: 2, offset: 0, total: 2) == 0,
            "the last page answers nothing")
        #expect(GoogleReaderRequestModifiers.continuation(returned: 1, offset: 0, total: 1) == 0,
            "a single item that is the whole answer")
        #expect(GoogleReaderRequestModifiers.continuation(returned: 3, offset: 2, total: 5) == 0,
            "3 plus 2 is 5, which is not below the total")
        #expect(GoogleReaderRequestModifiers.continuation(returned: 4, offset: 1, total: 6) == 5,
            "the value is the sum, which is below the total here")
    }
}
