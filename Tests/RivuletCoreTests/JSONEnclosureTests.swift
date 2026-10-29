import Foundation
import Testing
@testable import RivuletCore

/// The attachment rule the JSON Feed adapter writes. Ported from Miniflux
/// `internal/reader/json/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
@Suite struct JSONEnclosureTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/feed.json") throws -> ParsedFeed {
        try JSONFeedAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    /// The enclosures of the first entry of a document whose `items` array holds one item, read
    /// through the site URL, which is the home page here.
    private func enclosures(_ item: String, siteURL: String = "https://example.org/") throws
        -> [ParsedEnclosure] {
        try #require(parse("{\"home_page_url\": \"\(siteURL)\", \"items\": [ \(item) ]}")
            .entries.first?.enclosures)
    }

    /// `TestParsePodcast`: the attachment as the format declares it, with the size read as an
    /// `int64` field. The reference keeps `duration_in_seconds` in its struct and writes nothing
    /// with it, so the reading time is what the model starts with.
    @Test func podcastAttachmentIsReadAsTheFormatDeclaresIt() throws {
        let feed = try parse("{\"title\": \"The Record\", \"home_page_url\": \"http://therecord.co/\", "
            + "\"feed_url\": \"http://therecord.co/feed.json\", \"items\": [ { "
            + "\"id\": \"http://therecord.co/chris-parrish\", \"url\": \"http://therecord.co/chris-parrish\", "
            + "\"date_published\": \"2014-05-09T14:04:00-07:00\", \"attachments\": [ { "
            + "\"url\": \"http://therecord.co/downloads/The-Record-sp1e1-ChrisParrish.m4a\", "
            + "\"mime_type\": \"audio/x-m4a\", \"size_in_bytes\": 89970236, \"duration_in_seconds\": 6629 } ] } ] }",
            baseURL: "http://therecord.co/feed.json")

        let entry = try #require(feed.entries.first)
        #expect(entry.date.epochSeconds == 1399669440)
        #expect(entry.enclosures.count == 1)

        let enclosure = try #require(entry.enclosures.first)
        #expect(enclosure.url == "http://therecord.co/downloads/The-Record-sp1e1-ChrisParrish.m4a")
        #expect(enclosure.mimeType == "audio/x-m4a")
        #expect(enclosure.size == 89970236)
        #expect(entry.readingTimeMinutes == 0)
    }

    /// `TestParseItemWithoutAttachmentURL` — an attachment with no URL is skipped, so the entry has
    /// no enclosures at all.
    @Test func attachmentWithNoURLIsSkipped() throws {
        #expect(try enclosures("{\"attachments\": [ { \"url\": \"\", \"mime_type\": \"audio/x-m4a\", "
            + "\"size_in_bytes\": 0 } ]}").isEmpty)
    }

    /// `TestParseFeedWithRelativeAttachmentURL` — the URL is trimmed on its own and then resolved
    /// against the site URL.
    @Test func relativeAttachmentURLResolvesAgainstTheSiteURL() throws {
        let entry = try enclosures("{\"attachments\": [ { \"url\": \"   /attachment.mp3  \", "
            + "\"mime_type\": \"audio/mpeg\", \"size_in_bytes\": 123456 } ]}")
        #expect(entry.count == 1)
        #expect(try #require(entry.first).url == "https://example.org/attachment.mp3")
    }

    // MARK: - What the walk keeps

    /// Traced: the enclosures stay in the order the document wrote them, because the reference
    /// walks the array and appends as it goes.
    @Test func enclosuresStayInDocumentOrder() throws {
        let entry = try enclosures("{\"attachments\": [ { \"url\": \"https://example.org/b\", \"size_in_bytes\": 2 }, "
            + "{ \"url\": \"https://example.org/a\", \"size_in_bytes\": 1 } ]}")
        #expect(entry.map(\.url) == ["https://example.org/b", "https://example.org/a"])
    }

    /// Traced: `mime_type` is written as it was read, with no trim, which is what separates it from
    /// the URL.
    @Test func mimeTypeIsWrittenAsItWasRead() throws {
        let entry = try enclosures("{\"attachments\": [ { \"url\": \"https://example.org/a\", "
            + "\"mime_type\": \" audio/mpeg \", \"size_in_bytes\": 1 } ]}")
        #expect(try #require(entry.first).mimeType == " audio/mpeg ")
    }

    /// Traced: a value that cannot be resolved is skipped rather than written, which is what the
    /// reference logs a debug line for, so an attachment with a URL the resolver cannot read leaves
    /// nothing.
    @Test func attachmentURLThatCannotResolveIsSkipped() throws {
        let feed = try parse("{\"items\": [ { \"attachments\": [ { \"url\": \"/attachment.mp3\", "
            + "\"mime_type\": \"audio/mpeg\", \"size_in_bytes\": 1 } ] } ] }", baseURL: "://bad")
        #expect(try #require(feed.entries.first).enclosures.isEmpty)
    }

    // MARK: - What the field read keeps

    /// Traced: `null` assigns nothing to an `int64` field, so the field keeps what the shape
    /// started with, which is zero. The `ParseInt` rule itself is pinned in `JSONFieldReadTests`.
    @Test func nullSizeKeepsTheShapeValue() throws {
        let entry = try enclosures("{\"attachments\": [ { \"url\": \"https://example.org/a\", \"size_in_bytes\": null } ]}")
        #expect(try #require(entry.first).size == 0)
    }

    /// Traced: `attachments` is a slice of a struct, so an element is read against the element
    /// type, and an element that is not an object is the failure `literalStore` reports for that
    /// type.
    @Test func anElementThatIsNotAnObjectFailsAgainstTheElementType() {
        #expect(throws: JSONError.unmarshalTypeError(value: "string", target: "json.JSONAttachment")) {
            try enclosures("{\"attachments\": [ \"attachment\" ]}")
        }
    }

    /// Traced: a value that is not an array fails against the slice type, which is the word the
    /// reference's `array` production reports for the target it was called on.
    @Test func anObjectForAnArrayFieldFailsAgainstTheSliceType() {
        #expect(throws: JSONError.unmarshalTypeError(value: "object", target: "[]json.JSONAttachment")) {
            try enclosures("{\"attachments\": { \"url\": \"https://example.org/a\" }}")
        }
    }

    /// Traced: a string is not the type an int64 field accepts, so the failure names the value word
    /// the machine read and the type the field is.
    @Test func aStringForTheSizeFieldFailsAgainstTheFieldType() {
        #expect(throws: JSONError.unmarshalTypeError(value: "string", target: "int64")) {
            try enclosures("{\"attachments\": [ { \"url\": \"https://example.org/a\", \"size_in_bytes\": \"123\" } ]}")
        }
    }
}
