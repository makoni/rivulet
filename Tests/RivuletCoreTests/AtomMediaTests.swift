import Foundation
import Testing
@testable import RivuletCore

/// The attachments the Atom 1.0 adapter writes, and the media description it reads through the
/// content chain. Ported from Miniflux `internal/reader/atom/atom_10_test.go`, and from
/// `internal/reader/media/media_test.go` for the description rule the content chain reads through;
/// each case names the upstream test it comes from, and a traced case states the value the
/// reference produces.
///
/// The group order is the Atom one, which is where this format differs from `RSSMedia`: the media
/// thumbnails, then the `link` elements with relation `enclosure`, then the media contents, then
/// the media peer links, each group reading the entry's own elements before the group's, and the
/// whole list deduplicated by the resolved URL — except the thumbnails, which test the map on the
/// value as the element carries it, before the reference resolves it, which is the pair pinned
/// below.
@Suite struct AtomMediaTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private let mediaNamespace = " xmlns:media=\"http://search.yahoo.com/mrss/\">"

    private func enclosures(_ entryContent: String, baseURL: String = "https://example.org/") throws
        -> [ParsedEnclosure] {
        let feed = try Atom10Adapter.parse(baseURL: baseURL, data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\""
            + mediaNamespace + " <link href=\"https://example.org\"/>"
            + "<entry><link href=\"http://example.org/a\"/>\(entryContent)</entry></feed>").utf8), now: now)
        return try #require(feed.entries.first).enclosures
    }

    /// `TestParseEntryWithEnclosures` — the two enclosure links in the order they are written, with
    /// the type and the length read from the element.
    @Test func enclosureLinksKeepDocumentOrder() throws {
        #expect(try enclosures("<link rel=\"enclosure\" type=\"audio/mpeg\" title=\"MP3\""
            + " href=\"http://www.example.org/myaudiofile.mp3\" length=\"1234\"/>"
            + "<link rel=\"enclosure\" type=\"application/x-bittorrent\" title=\"BitTorrent\""
            + " href=\"http://www.example.org/myaudiofile.torrent\" length=\"4567\"/>")
            == [
                ParsedEnclosure(url: "http://www.example.org/myaudiofile.mp3", mimeType: "audio/mpeg",
                    size: 1234),
                ParsedEnclosure(url: "http://www.example.org/myaudiofile.torrent",
                    mimeType: "application/x-bittorrent", size: 4567),
            ])
    }

    /// `TestParseEntryWithRelativeEnclosureURL` and `TestParseEntryWithDuplicateEnclosureURL`: the
    /// href is trimmed before it is resolved, and the deduplication compares the resolved URL, so
    /// the two spellings of the same file are one attachment.
    @Test func enclosureURLIsTrimmedResolvedAndDeduplicated() throws {
        #expect(try enclosures("<link rel=\"enclosure\" type=\"audio/mpeg\" href=\"  /myaudiofile.mp3  \""
            + " length=\"1234\"/>")
            == [ParsedEnclosure(url: "https://example.org/myaudiofile.mp3", mimeType: "audio/mpeg",
                size: 1234)])

        #expect(try enclosures("<link rel=\"enclosure\" type=\"audio/mpeg\""
            + " href=\"http://www.example.org/myaudiofile.mp3\" length=\"1234\"/>"
            + "<link rel=\"enclosure\" type=\"audio/mpeg\" href=\"   http://www.example.org/myaudiofile.mp3  \""
            + " length=\"1234\"/>")
            == [ParsedEnclosure(url: "http://www.example.org/myaudiofile.mp3", mimeType: "audio/mpeg",
                size: 1234)])
    }

    /// `TestParseEntryWithoutEnclosureURL` — an enclosure with an empty href is not an attachment,
    /// even though it carries a length.
    @Test func enclosureWithAnEmptyHrefIsNotAnAttachment() throws {
        #expect(try enclosures("<link rel=\"enclosure\" href=\"\" length=\"0\"/>").isEmpty)
    }

    /// Traced: the length is read through `strconv.ParseInt`, which answers zero for a value it
    /// cannot read, and the Atom enclosure group drops a URL the reference cannot parse — the RSS
    /// `enclosure` is the group that keeps it, which `RSSMediaTests` pins.
    @Test func enclosureSizeIsTheParsedLength() throws {
        #expect(try enclosures("<link rel=\"enclosure\" type=\"audio/mpeg\""
            + " href=\"http://www.example.org/file.mp3\" length=\"not a number\"/>")
            == [ParsedEnclosure(url: "http://www.example.org/file.mp3", mimeType: "audio/mpeg", size: 0)])
    }

    /// Traced against `atom_10_adapter.go`: a URL the reference cannot parse is skipped, so neither
    /// the enclosure link nor a media element is an attachment. `%zz` is such a value — its percent
    /// escape is not two hex digits — so this is the only place the drop branch is reached. The RSS
    /// `enclosure` is the group that keeps the value as it was read, which `RSSMediaTests` pins.
    @Test func anUnresolvableURLIsNotAnAttachment() throws {
        let enclosureLink = try enclosures("<link rel=\"enclosure\" href=\"%zz\" length=\"1\"/>")
        let mediaContent = try enclosures("<media:content url=\"%zz\" medium=\"image\"/>")
        let mediaThumbnail = try enclosures("<media:thumbnail url=\"%zz\"/>")

        #expect(enclosureLink.isEmpty)
        #expect(mediaContent.isEmpty)
        #expect(mediaThumbnail.isEmpty)
    }

    /// `TestParseMediaGroup` — the thumbnails come before the contents, a duplicate URL is not
    /// listed twice, and an empty URL is not an attachment.
    @Test func mediaGroupWalksThumbnailsThenContents() throws {
        #expect(try enclosures("<media:group><media:title>Another title</media:title>"
            + "<media:content url=\"https://www.youtube.com/v/abcd\""
            + " type=\"application/x-shockwave-flash\" width=\"640\" height=\"390\"/>"
            + "<media:content url=\"   /v/efg  \" type=\"application/x-shockwave-flash\"/>"
            + "<media:content url=\"     \" type=\"application/x-shockwave-flash\"/>"
            + "<media:thumbnail url=\"https://www.example.org/duplicate-thumbnail.jpg\"/>"
            + "<media:thumbnail url=\"https://www.example.org/duplicate-thumbnail.jpg\"/>"
            + "<media:thumbnail url=\" /thumbnail2.jpg   \"/>"
            + "<media:thumbnail url=\"    \"/></media:group>")
            == [
                ParsedEnclosure(url: "https://www.example.org/duplicate-thumbnail.jpg", mimeType: "image/*",
                    size: 0),
                ParsedEnclosure(url: "https://example.org/thumbnail2.jpg", mimeType: "image/*", size: 0),
                ParsedEnclosure(url: "https://www.youtube.com/v/abcd",
                    mimeType: "application/x-shockwave-flash", size: 0),
                ParsedEnclosure(url: "https://example.org/v/efg",
                    mimeType: "application/x-shockwave-flash", size: 0),
            ])
    }

    /// `TestParseMediaElements` — the four groups in the order the Atom adapter walks them, with
    /// the type from `type`, from `medium`, or the fallback.
    @Test func mediaGroupsWalkInAtomOrder() throws {
        #expect(try enclosures("<media:thumbnail url=\"https://example.org/duplicated-thumbnail.jpg\"/>"
            + "<media:peerLink type=\"application/x-bittorrent\""
            + " href=\"   http://www.example.org/sampleFile.torrent   \"/>"
            + "<media:content url=\"https://example.org/relative/media.mp4\" medium=\"image\"/>"
            + "<media:peerLink type=\"application/x-bittorrent\" href=\" /sampleFile2.torrent\"/>")
            == [
                ParsedEnclosure(url: "https://example.org/duplicated-thumbnail.jpg", mimeType: "image/*",
                    size: 0),
                ParsedEnclosure(url: "https://example.org/relative/media.mp4", mimeType: "image/*", size: 0),
                ParsedEnclosure(url: "http://www.example.org/sampleFile.torrent",
                    mimeType: "application/x-bittorrent", size: 0),
                ParsedEnclosure(url: "https://example.org/sampleFile2.torrent",
                    mimeType: "application/x-bittorrent", size: 0),
            ])
    }

    /// Traced against `atom_10_adapter.go`: the thumbnail group checks the map on the trimmed URL
    /// before the reference resolves it, and writes the resolved value into the map, so the two
    /// spellings of one file are two attachments. The groups that check after resolving — the
    /// enclosure links, the contents and the peer links — compare the resolved value instead, which
    /// is what `RSSMediaTests` pins for the RSS copy; the difference is recorded in
    /// `docs/parity.md`.
    @Test func thumbnailsCheckTheMapBeforeTheyResolve() throws {
        #expect(try enclosures("<media:thumbnail url=\"https://example.org/thumbnail.jpg\"/>"
            + "<media:thumbnail url=\" /thumbnail.jpg \"/>")
            == [
                ParsedEnclosure(url: "https://example.org/thumbnail.jpg", mimeType: "image/*", size: 0),
                ParsedEnclosure(url: "https://example.org/thumbnail.jpg", mimeType: "image/*", size: 0),
            ])

        // The same pair read through the content group, which checks after resolving: there the two
        // spellings are one attachment.
        #expect(try enclosures("<media:content url=\"https://example.org/thumbnail.jpg\" medium=\"image\"/>"
            + "<media:content url=\" /thumbnail.jpg \" medium=\"image\"/>")
            == [ParsedEnclosure(url: "https://example.org/thumbnail.jpg", mimeType: "image/*", size: 0)])
    }

    // MARK: - Media description

    @Test(arguments: [
        // `TestDescription`: the type gate, then the link rule, then the newline.
        ("<media:description></media:description>", ""),
        ("<media:description type=\"html\">a &lt;b&gt;c&lt;/b&gt;</media:description>", "a <b>c</b>"),
        ("<media:description type=\"plain\">a\nhttp://www.example.org/</media:description>",
            "a<br><a href=\"http://www.example.org/\">http://www.example.org/</a>"),
        ("<media:description type=\"plain\">Link: https://example.com/path\n\nAnother: https://example.org"
            + "</media:description>", "Link: <a href=\"https://example.com/path\">https://example.com/path</a>"
            + "<br><br>Another: <a href=\"https://example.org\">https://example.org</a>"),
        // `TestFirstDescription` — an empty description is skipped, the first non-empty one is the
        // answer.
        ("<media:description></media:description><media:description>Something</media:description>",
            "Something"),
    ]) func mediaDescriptionRule(descriptionElement: String, expected: String) throws {
        #expect(try content(descriptionElement) == expected)
    }

    /// Traced: the reference trims nothing on this path — `First()` returns the value as it was
    /// read, so whitespace around it is part of the content.
    @Test func mediaDescriptionIsNotTrimmed() throws {
        #expect(try content("<media:description> x </media:description>") == " x ")
    }

    /// Traced against the `(?mi)` flags: the fold makes an uppercase spelling match, and the word
    /// boundary is what keeps a link that is stuck to a word out of the match.
    @Test func linkRuleIsFoldedAndBounded() throws {
        #expect(try content("<media:description>HTTPS://example.org/</media:description>")
            == "<a href=\"HTTPS://example.org/\">HTTPS://example.org/</a>")
        #expect(try content("<media:description>xhttp://example.org/</media:description>")
            == "xhttp://example.org/")
    }

    /// Traced: the entry's own descriptions come before the group's, which is the merge order the
    /// media rules use for every group.
    @Test func descriptionChainReadsEntryBeforeGroup() throws {
        #expect(try content("<media:description>Entry</media:description>"
            + "<media:group><media:description>Group</media:description></media:group>") == "Entry")
        #expect(try content("<media:group><media:description>Group</media:description></media:group>")
            == "Group")
    }

    private func content(_ entryContent: String) throws -> String {
        try entry(entryContent).content
    }

    private func entry(_ entryContent: String) throws -> ParsedEntry {
        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\"" + mediaNamespace
                + "<link href=\"http://example.org\"/><entry>\(entryContent)</entry></feed>").utf8), now: now)
        return try #require(feed.entries.first)
    }
}
