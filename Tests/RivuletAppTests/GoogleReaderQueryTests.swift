import Testing
@testable import RivuletApp

/// The query read the stream filter uses — Go's `r.URL.Query()`, which the reference reads through
/// `request.QueryStringParam` and `QueryStringParamList` (`internal/http/request/params.go` at
/// `c4d54f87`). The goldens are the reference's own output at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the pairs are
/// split on `&`, and an empty pair is skipped rather than read as a name, which a patch that kept
/// it fails on `?&a=b`; a pair that carries a `;` is skipped and the read continues with the pairs
/// after it — the reference reports that as an error for the pair, and `Query()` discards the
/// error, so what answers is what parsed — which a patch that treated `;` as a pair separator fails
/// on `?a=b&c;d=e&f=g`, where the names are `a` and `f` and not `a` alone; a pair with no `=` is a
/// name with one empty value, which a patch that skipped such a pair fails on `?a=b&a`; `+` in
/// either the name or the value is a space, while `%2B` is the character itself, which a patch that
/// read `+` as itself fails on the name `a b`; a pair whose name or value cannot be unescaped is
/// skipped and the rest of the query is still read, which a patch that stopped the whole read fails
/// on `?a=b&%zz&f=g`; the value read is the first one with that name, while the list read gives
/// them in the order the pairs came in, which a patch that ordered them the other way fails on
/// `?s=feed/2&s=feed/1`; and the name is unescaped before it is compared, so `?a%20b=c` answers for
/// the name `a b`.
///
/// What these pins cannot fail on: that a name the query does not carry and a name whose value is
/// empty answer the same — Go's `Values` answers `""` for both, which is why the guards read the
/// answer rather than the presence; the order the names come back in, because Go's `Values` is a
/// map, so the order is what the pins read per name; and the error `Query()` discards, which has no
/// answer this side can show — the merged form read is where an error is reported, and
/// `GoogleReaderAuthTests` pins that the handler answers it before reading any value.
@Suite struct GoogleReaderQueryTests {
    @Test func thePairsAreSplitOnTheAmpersandAndAnEmptyPairIsSkipped() throws {
        let query = GoogleReaderQuery(query: "a=1&&b=2")
        #expect(query.values(named: "a") == ["1"], "the pair before the empty one")
        #expect(query.values(named: "b") == ["2"], "and the pair after it is still read")

        // A patch that read an empty pair as a name answered `[""]` for the empty name here.
        let empty = GoogleReaderQuery(query: "&a=b")
        #expect(empty.values(named: "").isEmpty, "the empty pair is not a name")
        #expect(empty.values(named: "a") == ["b"], "and the pair after it is read")
    }

    @Test func aPairWithNoEqualsSignIsANameWithOneEmptyValue() throws {
        // Go's `parseQuery` appends an empty value for a pair with no `=`, which is what
        // `parseItemIDsFromRequest` reads before it parses the id, so `?i` is one value for that
        // read.
        let query = GoogleReaderQuery(query: "a=b&a")
        #expect(query.values(named: "a") == ["b", ""], "the pair with no `=` gives an empty value")
        #expect(query.value(named: "a") == "b", "and `Get` answers the first value")

        // A name that is the empty string is still a name.
        #expect(GoogleReaderQuery(query: "=v").values(named: "") == ["v"], "the empty name")
    }

    @Test func aSemicolonSkipsItsPairAndTheReadContinues() throws {
        // `Query()` discards the error the pair produced, so the pairs that parsed are what
        // answers.
        let query = GoogleReaderQuery(query: "a=b&c;d=e&f=g")
        #expect(query.values(named: "a") == ["b"], "the pair read before it")
        #expect(query.values(named: "c").isEmpty, "the pair that carries the `;` is not read")
        #expect(query.values(named: "f") == ["g"], "and the pairs after it are read")

        // A patch that treated `;` as a pair separator would answer `["c"]` for `x` here.
        #expect(GoogleReaderQuery(query: "a=b;x=c").values(named: "x").isEmpty,
            "the semicolon is not a separator, so the whole pair is the skipped one")
        #expect(GoogleReaderQuery(query: ";a=b").values(named: "a").isEmpty,
            "a pair that starts with the semicolon is skipped too")
    }

    @Test func aPairThatCannotBeUnescapedIsSkippedAndTheRestIsStillRead() throws {
        let query = GoogleReaderQuery(query: "a=b&%zz&f=g")
        #expect(query.values(named: "a") == ["b"], "the pair before it")
        #expect(query.values(named: "f") == ["g"], "the pair after it")

        // A patch that stopped the whole read at the bad pair answered nothing for `a` here.
        #expect(GoogleReaderQuery(query: "=%zz&a=v").values(named: "a") == ["v"],
            "the pair whose name cannot be unescaped is skipped, and the read continues")
    }

    @Test func thePlusIsASpaceAndPercentEscapeIsTheCharacter() throws {
        let query = GoogleReaderQuery(query: "a+b=c+d")
        #expect(query.value(named: "a b") == "c d", "the plus is a space on both sides")
        #expect(query.values(named: "a+b").isEmpty, "so the name with the plus is not this name")
        #expect(GoogleReaderQuery(query: "b=%2Bc").values(named: "b") == ["+c"],
            "the percent form is the character itself")
        #expect(GoogleReaderQuery(query: "a%20b=c").values(named: "a b") == ["c"],
            "the name is unescaped before it is compared")
    }

    @Test func theFirstValueWithTheNameIsWhatGetAnswers() throws {
        let query = GoogleReaderQuery(query: "s=feed/2&s=feed/1")
        #expect(query.value(named: "s") == "feed/2", "the first pair with the name is the one `Get` reads")
        #expect(query.values(named: "s") == ["feed/2", "feed/1"],
            "and the list read gives them in the order the pairs came in")
    }

    @Test func theValuesTheStreamFilterReadsMatchTheReferenceOutput() throws {
        // Each row is the reference's own output for the query and the name the filter reads, from
        // the scratch run at the toolchain `go.mod` pins.
        let goldens: [(query: String, name: String, values: [String])] = [
            ("a", "a", [""]),
            ("a=b&a=c", "a", ["b", "c"]),
            ("a+b=c+d", "a b", ["c d"]),
            ("a=b;x=c", "a", []),
            ("a=b;x=c", "x", []),
            ("a=%zz&b=c", "b", ["c"]),
            ("a=1&&b=2", "a", ["1"]),
            ("a=1&&b=2", "b", ["2"]),
            ("a=%41&b=%2Bc", "a", ["A"]),
            ("a=%41&b=%2Bc", "b", ["+c"]),
            (";a=b", "a", []),
            ("a=b&c;d=e&f=g", "c", []),
            ("a=b&c;d=e&f=g", "f", ["g"]),
            ("i=1&i=%zz&i=2", "i", ["1", "2"]),
            ("s=feed/1&s=bogus&s=feed/2", "s", ["feed/1", "bogus", "feed/2"]),
            ("s=feed/1&s=&s=%20feed/2", "s", ["feed/1", "", " feed/2"]),
            ("output=json", "output", ["json"]),
            ("output=atom", "output", ["atom"]),
            ("", "output", []),
            ("n=&c=&r=&ot=&nt=", "n", [""]),
            ("n=+50", "n", [" 50"]),
            ("n=50%20", "n", ["50 "]),
            ("ot=1700000000&nt=1800000000", "ot", ["1700000000"]),
            ("ot=1700000000&nt=1800000000", "nt", ["1800000000"]),
            ("ot=-1", "ot", ["-1"]),
            ("n=0x10", "n", ["0x10"]),
            ("c=0000000000000000000000000000000000000000000000000000000000000005", "c",
                ["0000000000000000000000000000000000000000000000000000000000000005"]),
        ]
        for golden in goldens {
            let query = GoogleReaderQuery(query: golden.query)
            #expect(query.values(named: golden.name) == golden.values,
                "the reference's answer for \(golden.query) read as \(golden.name)")
            #expect(query.value(named: golden.name) == golden.values.first ?? "",
                "`Get` answers the first of them, or nothing when the name is not carried")
        }
    }
}
