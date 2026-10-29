import Foundation
import Testing
@testable import RivuletCore

/// The entry identity the Atom 1.0 adapter writes. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The chain is the ID, then the original link, and both are hashed as the reference read them: the
/// ID is the character data with no trim, and the link is the href as `originalLink()` trimmed it,
/// before anything is resolved against the site URL.
@Suite struct AtomHashTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func hash(_ entryContent: String) throws -> String {
        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
            + "<entry>\(entryContent)</entry></feed>").utf8), now: now)
        return try #require(feed.entries.first).hash
    }

    /// `TestParseAtomSample` — the ID is the identity when the entry has both an ID and a link.
    @Test func idHashesBeforeTheLink() throws {
        #expect(try hash("<link href=\"http://example.org/a\"/>"
            + "<id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>")
            == "3841e5cf232f5111fc5841e9eba5f4b26d95e7d7124902e0f7272729d65601a6")
    }

    /// Traced: with no ID the original link is hashed, and it is hashed as the href was read, not
    /// as the resolved entry URL, so a relative href hashes the relative value.
    @Test func linkHashesWhenThereIsNoID() throws {
        #expect(try hash("<link href=\"http://example.org/a\"/>")
            == "6a2d6a47a2828fe021aefacd33629435a066843485eac81b46bf451f79461bdb")
        #expect(try hash("<link href=\"/a\"/>")
            == "6a50dc8584134c7de537c0052ff6d236bf874355e050c90523e0c5ff2a543a28")
    }

    /// Traced: the ID is hashed as the field read it, so the whitespace around it is part of the
    /// input.
    @Test func idIsHashedAsItWasRead() throws {
        #expect(try hash("<id> urn:uuid:x </id>")
            == "9efd7fea2d7819cc8d21dfe536f8fe35b9fa6383cecd519fb564e23368ce2a78")
    }

    /// Traced: with nothing to hash the identity stays what the model starts with, which is the
    /// empty string — the reference calls `crypto.SHA256` only for a value that is not empty.
    @Test func entryWithNeitherIDNorLinkHasNoHash() throws {
        #expect(try hash("<updated>2003-12-13T18:30:02Z</updated>") == "")
    }

    /// `TestParseAtom03` — the same chain for Atom 0.3, which `Atom03Tests` asserts for the whole
    /// entry.
    @Test func atom03HashesItsIdTheSameWay() throws {
        #expect(try hashAtom03("<id>tag:diveintomark.org,2003:3.2397</id>"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/a\"/>")
            == "b70d30334b808f32e66eb19fabb263525cecd18f205720b583e84f7f295cf728")
    }

    private func hashAtom03(_ entryContent: String) throws -> String {
        let feed = try Atom03Adapter.parse(baseURL: "http://diveintomark.org/",
            data: Data(("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\">"
                + "<entry>\(entryContent)</entry></feed>").utf8), now: now)
        return try #require(feed.entries.first).hash
    }
}
