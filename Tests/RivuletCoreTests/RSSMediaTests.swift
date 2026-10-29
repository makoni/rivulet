import Foundation
import Testing
@testable import RivuletCore

/// The attachments the RSS adapter writes. Ported from Miniflux
/// `internal/reader/rss/parser_test.go`. The order is the order `findEntryEnclosures` walks: the
/// media thumbnails, the `rss:enclosure` elements, the media contents, then the media peer links,
/// with each group reading its own elements first and then the group's, and the whole list
/// deduplicated by the resolved URL.
@Suite struct RSSMediaTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func entry(_ item: String, namespaces: String = "", siteLink: String = "https://example.org") throws
        -> ParsedEntry {
        let document = "<rss version=\"2.0\"" + namespaces + "><channel><title>Example</title><link>"
            + siteLink + "</link>" + item + "</channel></rss>"
        return try #require(RSSAdapter.parse(baseURL: siteLink, data: Data(document.utf8), now: now).entries.first)
    }

    private let media = " xmlns:media=\"http://search.yahoo.com/mrss/\""
    private func enclosure(_ url: String, _ mimeType: String, _ size: Int) -> ParsedEnclosure {
        ParsedEnclosure(url: url, mimeType: mimeType, size: size)
    }

    /// `TestParseEntryWithMediaGroup`: the group's elements come after the item's own, a duplicate
    /// URL is not listed twice, an empty URL is not an attachment, and `fileSize` is the size.
    @Test func mediaGroupWalksAfterTheItemEnclosure() throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<enclosure type=\"application/x-bittorrent\" url=\"https://example.org/file3.torrent\""
            + " length=\"670053113\"></enclosure><media:group>"
            + "<media:content type=\"application/x-bittorrent\" url=\"https://example.org/file1.torrent\"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\"https://example.org/file2.torrent\""
            + " isDefault=\"true\"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\"https://example.org/file3.torrent\"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\"https://example.org/file4.torrent\"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\" https://example.org/file4.torrent \"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\" file5.torrent  \" fileSize=\"42\"></media:content>"
            + "<media:content type=\"application/x-bittorrent\" url=\"  \" fileSize=\"42\"></media:content>"
            + "</media:group><media:thumbnail url=\"https://example.org/image.jpg\" /></item>",
            namespaces: media)

        #expect(parsed.enclosures == [
            enclosure("https://example.org/image.jpg", "image/*", 0),
            enclosure("https://example.org/file3.torrent", "application/x-bittorrent", 670053113),
            enclosure("https://example.org/file1.torrent", "application/x-bittorrent", 0),
            enclosure("https://example.org/file2.torrent", "application/x-bittorrent", 0),
            enclosure("https://example.org/file4.torrent", "application/x-bittorrent", 0),
            enclosure("https://example.org/file5.torrent", "application/x-bittorrent", 42),
        ])
    }

    /// Traced: the RSS enclosure is the group that keeps a URL the reference cannot resolve, while
    /// the media groups skip it. `%zz` is a value `url.Parse` cannot read — its percent escape is
    /// not two hex digits — so this is where the two branches are reached, on the same value.
    @Test func theEnclosureKeepsAnUnresolvableURL() throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<enclosure url=\"%zz\" type=\"audio/mpeg\" length=\"42\"></enclosure>"
            + "<media:content url=\"%zz\" medium=\"image\"></media:content></item>", namespaces: media)

        #expect(parsed.enclosures == [enclosure("%zz", "audio/mpeg", 42)])
    }

    /// `TestParseEntryWithMediaContent`: the thumbnail is read before the content, and the type
    /// comes from `type`, or from `medium`, or is the fallback.
    @Test func mediaContentMimeTypeFallsBackToTheMedium() throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<media:thumbnail url=\"https://example.org/thumbnail.jpg\" />"
            + "<media:thumbnail url=\"https://example.org/thumbnail.jpg\" />"
            + "<media:thumbnail url=\" thumbnail.jpg  \" />"
            + "<media:thumbnail url=\"   \" />"
            + "<media:content url=\"https://example.org/media1.jpg\" medium=\"image\"></media:content>"
            + "<media:content url=\"   /media2.jpg   \" medium=\"video\" />"
            + "<media:content url=\"https://example.org/media3.jpg\" medium=\"audio\" />"
            + "<media:content url=\"https://example.org/media4.jpg\" />"
            + "<media:content url=\"    \" medium=\"image\" /></item>", namespaces: media)

        #expect(parsed.enclosures == [
            enclosure("https://example.org/thumbnail.jpg", "image/*", 0),
            enclosure("https://example.org/media1.jpg", "image/*", 0),
            enclosure("https://example.org/media2.jpg", "video/*", 0),
            enclosure("https://example.org/media3.jpg", "audio/*", 0),
            enclosure("https://example.org/media4.jpg", "application/octet-stream", 0),
        ])
    }

    /// `TestParseEntryWithMediaPeerLink`: a peer link reads its `href`, and the resolved URL is
    /// what the dedup compares.
    @Test func mediaPeerLinkUsesHref() throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<media:peerLink type=\"application/x-bittorrent\" href=\"https://example.org/file.torrent\" />"
            + "<media:peerLink type=\"application/x-bittorrent\" href=\"https://example.org/file.torrent\" />"
            + "<media:peerLink type=\"application/x-bittorrent\" href=\" file2.torrent   \" />"
            + "<media:peerLink type=\"application/x-bittorrent\" href=\"    \" />"
            + "<media:peerLink href=\"https://example.org/file3.torrent\" /></item>", namespaces: media)

        #expect(parsed.enclosures == [
            enclosure("https://example.org/file.torrent", "application/x-bittorrent", 0),
            enclosure("https://example.org/file2.torrent", "application/x-bittorrent", 0),
            enclosure("https://example.org/file3.torrent", "application/octet-stream", 0),
        ])
    }

    /// `TestParseEntryWithFeedBurnerEnclosures`: the original link replaces the proxy URL when the
    /// enclosure URL ends with its filename, which is the only case the check reads.
    @Test(arguments: [
        ("http://feedproxy.google.com/~r/example/~5/lp/File.mp3", "http://example.org/67ca/File.mp3",
            "http://example.org/67ca/File.mp3"),
        ("http://feedproxy.google.com/~r/example/~5/lp/Other.mp3", "http://example.org/67ca/File.mp3",
            "http://feedproxy.google.com/~r/example/~5/lp/Other.mp3"),
        ("http://feedproxy.google.com/~r/example/~5/lp/File.mp3", "/67ca/File.mp3",
            "http://example.org/67ca/File.mp3"),
    ]) func feedBurnerOriginalLink(enclosureURL: String, originalLink: String, expected: String) throws {
        let parsed = try entry("<item><link>http://example.org/entries/1</link>"
            + "<enclosure url=\"" + enclosureURL + "\" length=\"1\" type=\"audio/mpeg\" />"
            + "<feedburner:origEnclosureLink>" + originalLink + "</feedburner:origEnclosureLink></item>",
            namespaces: " xmlns:feedburner=\"http://rssnamespace.org/feedburner/ext/1.0\"",
            siteLink: "http://example.org")
        #expect(try #require(parsed.enclosures.first).url == expected)
    }

    /// Traced from `path.Base`: a value that is only separators is the filename `/`, which every
    /// URL that ends with a separator has, so the enclosure takes the original link.
    @Test func anOriginalLinkOfOnlySeparatorsIsTheFilename() throws {
        let parsed = try entry("<item><link>http://example.org/entries/1</link>"
            + "<enclosure url=\"http://example.org/67ca/File.mp3/\" length=\"1\" type=\"audio/mpeg\" />"
            + "<feedburner:origEnclosureLink>/</feedburner:origEnclosureLink></item>",
            namespaces: " xmlns:feedburner=\"http://rssnamespace.org/feedburner/ext/1.0\"",
            siteLink: "http://example.org")
        #expect(try #require(parsed.enclosures.first).url == "http://example.org/")
    }

    /// `TestParseEntryWithIncorrectEnclosureLength`: a length that is not a number is zero, and an
    /// empty one is zero before the parse is even attempted.
    @Test(arguments: [
        ("42", 42),
        ("invalid", 0),
        (" ", 0),
        (" 42 ", 0),
    ]) func enclosureLength(length: String, expected: Int) throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<enclosure url=\"https://example.org/a.mp3\" length=\"" + length + "\" type=\"audio/mpeg\" /></item>")
        #expect(try #require(parsed.enclosures.first).size == expected)
    }

    /// An empty enclosure URL is not an attachment, which is what
    /// `TestParseEntryWithEmptyEnclosureURL` pins, and the URL is resolved against the site URL,
    /// which is what `TestParseEntryWithRelativeEnclosureURL` pins.
    @Test(arguments: [
        (" /files/file.mp3  ", "https://example.org/files/file.mp3"),
        (" ", ""),
    ]) func enclosureURLIsTrimmedAndResolved(url: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/entries/1</link>"
            + "<enclosure url=\"" + url + "\" length=\"0\" /></item>")
        #expect(parsed.enclosures.count == (expected.isEmpty ? 0 : 1))
        if !expected.isEmpty { #expect(try #require(parsed.enclosures.first).url == expected) }
    }
}
