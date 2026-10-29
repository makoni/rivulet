import Foundation
import Testing
@testable import RivuletCore

/// The entry identity the RSS adapter writes. Ported from Miniflux
/// `internal/reader/rss/parser_test.go`. The reference keeps the first occurrence of a GUID stable
/// so entries already stored still match, and disambiguates a later collision with the entry URL or,
/// when there is no URL to use, with the position.
@Suite struct RSSHashTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func hashes(_ channel: String, baseURL: String = "https://example.org/") throws -> [String] {
        let document = "<rss version=\"2.0\"><channel>" + channel + "</channel></rss>"
        let feed = try RSSAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
        return feed.entries.map(\.hash)
    }

    /// `TestParseEntriesWithUniqueGUIDsAreUnchanged` — the regression guard: a feed with unique GUIDs
    /// keeps `SHA256(guid)`.
    @Test func uniqueGUIDsHashTheGUIDAlone() throws {
        #expect(try hashes("<link>https://example.org/</link>"
            + "<item><title>Item A</title><link>https://example.org/a</link>"
            + "<guid isPermaLink=\"false\">guid-a</guid></item>"
            + "<item><title>Item B</title><link>https://example.org/b</link>"
            + "<guid isPermaLink=\"false\">guid-b</guid></item>")
            == [
                "2b13a8de1741fb778d7e733e7a888088cb578d22e5ec6d40e0a88f82d4829cbd",
                "33ce1b8657a81c6a49590313a36325e44683f27229e96faa690f9dc7b2a75d2a",
            ])
    }

    /// `TestParseEntriesWithDuplicateGUIDAndDistinctLinks` — the first occurrence keeps the historical
    /// hash, and each later one is disambiguated with the entry URL, which is what makes the three
    /// hashes different.
    @Test func duplicateGUIDsAreDisambiguatedByTheEntryURL() throws {
        #expect(try hashes("<link>https://example.org/</link>"
            + "<item><title>Item A</title><link>https://example.org/a</link>"
            + "<guid isPermaLink=\"false\">dup-guid</guid></item>"
            + "<item><title>Item B</title><link>https://example.org/b</link>"
            + "<guid isPermaLink=\"false\">dup-guid</guid></item>"
            + "<item><title>Item C</title><link>https://example.org/a</link>"
            + "<guid isPermaLink=\"false\">dup-guid</guid></item>")
            == [
                "22561495b53d916c228504600fda7c06cefc55a80395bbdf007102a6e9070d3f",
                "3479bd288c08f8d2f8e992aa511a267ee50b18e22a4c475a4862c15c4d4f675b",
                "8e4bb51d800e7a0db6b81b48d09af4711f8a25e00d09251e3d9f675e02bfe11e",
            ])
    }

    /// `TestParseEntriesWithDuplicateGUIDAndNoLink`: the entry URL falls back to the site URL, so a
    /// collision is disambiguated with that URL rather than with the position — the position branch is not
    /// reached when anything can be resolved.
    @Test func duplicateGUIDsWithoutALinkUseTheSiteURLFallback() throws {
        #expect(try hashes("<link>https://example.org/</link>"
            + "<item><title>Item A</title><guid isPermaLink=\"false\">dup-guid</guid></item>"
            + "<item><title>Item B</title><guid isPermaLink=\"false\">dup-guid</guid></item>")
            == [
                "22561495b53d916c228504600fda7c06cefc55a80395bbdf007102a6e9070d3f",
                "175d6d57a61533fb553c5d9bc3d52aa9092553a7e0ae473e3536c32c87cfa418",
            ])
    }

    /// Traced: the position is the last resort, and the reference reaches it only when the entry has no
    /// URL at all, which needs a base URL nothing can be resolved against. With an empty one, the site URL
    /// stays empty, so the second hash is `SHA256(guid + "|" + position)`.
    @Test func positionIsUsedOnlyWhenTheEntryHasNoURL() throws {
        #expect(try hashes("<item><title>Item A</title><guid isPermaLink=\"false\">dup-guid</guid></item>"
            + "<item><title>Item B</title><guid isPermaLink=\"false\">dup-guid</guid></item>",
            baseURL: "")
            == [
                "22561495b53d916c228504600fda7c06cefc55a80395bbdf007102a6e9070d3f",
                "0047844a92fcaf7b977ea1f2ee3785d4e9d9292dac6ae7edb2d06db1066c1856",
            ])
    }

    /// `TestParseEntryWithoutLink` and `TestParseEntryWithoutLinkAndWithoutGUID`: without a GUID the
    /// hash is the entry URL, and without a URL it is the title plus the content.
    @Test func hashChainWithoutAGUID() throws {
        #expect(try hashes("<link>https://example.org/</link>"
            + "<item><guid isPermaLink=\"false\">1234</guid></item>"
            + "<item><title>Item 1</title></item>"
            + "<item><title>Item 2</title></item>")
            == [
                "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4",
                "c5ddfeffb275254140796b8c080f372d65ebb1b0590e238b191f595d5fcd32ca",
                "0a937478f9bdbfca2de5cdeeb5ee7b09678a3330fc7cc5b05169a50d4516c9a3",
            ])
    }

    /// Traced: the URL branch hashes the URL as `findEntryURL` returned it, before it is resolved,
    /// while the stored URL is the resolved one.
    @Test func urlBranchHashesTheUnresolvedURL() throws {
        let document = "<rss version=\"2.0\"><channel><link>https://example.org/</link>"
            + "<item><link>item.html</link></item></channel></rss>"
        let feed = try RSSAdapter.parse(baseURL: "https://example.org/", data: Data(document.utf8), now: now)
        let entry = try #require(feed.entries.first)
        #expect(entry.url == "https://example.org/item.html")
        #expect(entry.hash == "d28cdc3d2827f383e51fbc9a9d76bc6029b82d679f1efdccc6951ec3e10e48fb")
    }
}
