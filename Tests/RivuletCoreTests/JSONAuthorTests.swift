import Foundation
import Testing
@testable import RivuletCore

/// The author rule the JSON Feed adapter writes: the names from the four places the format
/// declares, sorted by the byte comparison, deduplicated, and joined with a comma and a
/// space. Ported from Miniflux `internal/reader/json/parser_test.go`; each case names the
/// upstream test it comes from, and a traced case states the value the reference produces.
///
/// The reference keeps an author's website and avatar but writes nothing with
/// them, so the model field here is the name alone, which the last case pins.
@Suite struct JSONAuthorTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String) throws -> ParsedFeed {
        try JSONFeedAdapter.parse(baseURL: "https://example.org/feed.json", data: Data(document.utf8), now: now)
    }

    /// The entry author for a document whose `items` array holds one item.
    private func author(_ item: String) throws -> String {
        try #require(parse("{\"items\": [ \(item) ]}").entries.first?.author)
    }

    // MARK: - The places the format declares an author

    /// `TestParseItemWithLegacyAuthorField` — the deprecated feed author is
    /// one of the names an entry falls back to, and the reference reads the
    /// author's website and avatar into its struct without using either.
    @Test func feedAuthorIsTheFallbackName() throws {
        let feed = try parse("{\"author\": { \"name\": \"Brent Simmons\", \"url\": \"http://example.org/\", "
            + "\"avatar\": \"https://example.org/avatar.png\" }, \"items\": [ { } ]}")
        #expect(try #require(feed.entries.first).author == "Brent Simmons")
    }

    /// `TestParseItemWithMultipleAuthorFields` — both the 1.1 array and the deprecated
    /// field are read, so both names are in the list, and the list is the sorted one.
    @Test func feedAuthorsAndTheDeprecatedFieldAreBothRead() throws {
        let feed = try parse("{\"author\": { \"name\": \"Deprecated Author Field\" }, "
            + "\"authors\": [ { \"name\": \"Brent Simmons\" } ], \"items\": [ { } ]}")
        #expect(try #require(feed.entries.first).author == "Brent Simmons, Deprecated Author Field")
    }

    /// `TestParseItemWithMultipleDuplicateAuthors` — an item's own authors are the ones
    /// the entry prefers, and a repeated name is inserted once, in sorted position.
    @Test func itemAuthorsAreSortedAndDeduplicated() throws {
        #expect(try author("{\"authors\": [ { \"name\": \"Author B\" }, { \"name\": \"Author A\" }, "
            + "{ \"name\": \"Author B\" } ]}") == "Author A, Author B")
    }

    /// `TestParseItemWithAuthorsObject` — `authors` is a slice, but the reference's
    /// `UnmarshalJSON` accepts a single object for it, which is the second branch of the leniency.
    @Test func anObjectForAuthorsIsAccepted() throws {
        #expect(try author("{\"authors\": { \"name\": \"Example Author\" }}") == "Example Author")
    }

    // MARK: - The leniency

    /// Traced: the first branch is the array, the second is a single object,
    /// and a value that is neither is ignored silently — the method returns
    /// without assigning — so a second member with such a value leaves the
    /// name the earlier member gave, which is what a repeated key separates.
    @Test func aValueThatIsNeitherBranchsAnswerLeavesTheEarlierAssignment() throws {
        let feed = try parse("{\"authors\": [ { \"name\": \"Fed Author\" } ], \"authors\": \"not an author\", "
            + "\"items\": [ { \"authors\": [ { \"name\": \"Item Author\" } ], \"authors\": 1 } ]}")
        #expect(try #require(feed.entries.first).author == "Fed Author, Item Author")
    }

    /// Traced: a bad element fails the whole array attempt rather than that
    /// element, because `UnmarshalJSON` tries the array as one value and the
    /// single-object attempt fails too, so all the item's authors are dropped.
    @Test func aBadElementDropsAllTheItemAuthors() throws {
        let feed = try parse("{\"author\": { \"name\": \"Feed Author\" }, \"items\": [ { \"authors\": "
            + "[ { \"name\": \"Item Author\" }, \"not an author\" ] } ]}")
        #expect(try #require(feed.entries.first).author == "Feed Author")
    }

    /// Traced: `null` is the array branch's answer, and that branch assigns —
    /// `SetZero` for a slice target, through the `Unmarshal` the method calls — so a
    /// null key clears an earlier assignment, which is what the case above separates.
    @Test func nullAuthorsClearAnEarlierAssignment() throws {
        let feed = try parse("{\"authors\": [ { \"name\": \"Fed Author\" } ], \"authors\": null, "
            + "\"items\": [ { \"authors\": [ { \"name\": \"Item Author\" } ], \"authors\": null } ]}")
        #expect(try #require(feed.entries.first).author == "")
    }

    /// Traced: the singular `author` is a plain struct field, not one with the
    /// leniency, so a value that is not an object is the failure the field read
    /// reports — the word for the value the machine read, and the type the field is.
    @Test func aNonObjectForTheAuthorFieldFailsTheParse() {
        #expect(throws: JSONError.unmarshalTypeError(value: "array", target: "json.JSONAuthor")) {
            try parse("{\"author\": [ { \"name\": \"A\" } ], \"items\": []}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "string", target: "json.JSONAuthor")) {
            try parse("{\"items\": [ { \"author\": \"A\" } ]}")
        }
    }

    // MARK: - Names

    /// Traced: the four places are the feed authors, the item authors, the item
    /// author and the feed author, and the list the entry gets is the sorted
    /// one, so the order the format declares them in does not decide the output.
    @Test func theFourPlacesAreCollectedAndSorted() throws {
        let feed = try parse("{\"authors\": [ { \"name\": \"Fed A\" }, { \"name\": \"Fed D\" } ], "
            + "\"items\": [ { \"authors\": [ { \"name\": \"Item B\" } ], \"author\": { \"name\": \"Item C\" } } ]}")
        #expect(try #require(feed.entries.first).author == "Fed A, Fed D, Item B, Item C")
    }

    /// Traced: the name is trimmed before the search, which is `JSONAuthor.name()`,
    /// and an author whose name is nothing after the trim is not a name at all.
    @Test func namesAreTrimmedBeforeTheyAreCompared() throws {
        #expect(try author("{\"authors\": [ { \"name\": \" \" }, { \"name\": \"  Ben  \" } ]}") == "Ben")
    }

    /// Traced: only the name is written to the model. The reference reads
    /// an author's website and avatar into its struct and uses neither
    /// in `BuildFeed`, so the author string here is the name alone.
    @Test func theAuthorFieldIsTheNameAlone() throws {
        #expect(try author("{\"author\": { \"name\": \"Ann\", \"url\": \"http://example.org/\", "
            + "\"avatar\": \"https://example.org/avatar.png\" }}") == "Ann")
    }
}
