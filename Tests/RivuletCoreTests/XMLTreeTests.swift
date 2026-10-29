import Foundation
import Testing
@testable import RivuletCore

/// The tree the reader builds, read the three ways the reference reads a value out of it. The tree
/// keeps the content in document order, because the two rules do not agree: `",chardata"` keeps the
/// character data at the element's own level, while `innerContent` writes every character token it
/// reads, including the ones inside a child element.
///
/// The reference keeps `innerxml` as the bytes it read. The tree keeps character data already
/// decoded, so `innerMarkup` is the markup with the decoded text; that is recorded in
/// `docs/parity.md`. The CDATA marker is kept, because that is what the CDATA rule reads.
@Suite struct XMLTreeTests {
    /// `TestParseItemTitleWithInnerHTML` — `innerContent` writes the tokens in the order they come,
    /// so the text inside a child is part of the value.
    @Test func innerContentKeepsDocumentOrderAcrossChildren() throws {
        let title = try #require(
            try XMLReader.read(Data("<item><title>Test: <b>bold</b></title></item>".utf8))
                .child(local: "title")
        )
        #expect(title.innerContent == "Test: bold")

        // `Element.Data` keeps only the level it is read at, which is what `text` is.
        #expect(title.text == "Test: ")
    }

    /// `TestParseEntryWithAuthorAndCDATA` — a CDATA section is kept as its own run, marker included,
    /// which is what `strings.Contains(Inner, "<![CDATA[")` reads.
    @Test func aCDATARunIsKeptWithItsMarker() throws {
        let author = try #require(
            try XMLReader.read(Data("<item><author>by <![CDATA[Foo Bar]]></author></item>".utf8))
                .child(local: "author")
        )
        #expect(author.text == "by Foo Bar")
        #expect(author.innerMarkup == "by <![CDATA[Foo Bar]]>")
    }

    /// `TestParseEntryWithAuthorAndInnerHTML` — the inner content is the markup as well as the text,
    /// so an author that is a link is not read as the link's text alone.
    @Test func innerMarkupKeepsTheMarkupOfChildren() throws {
        let author = try #require(
            try XMLReader.read(
                Data("<item><author>by <a href=\"/author/foobar\">Foo Bar</a></author></item>".utf8)
            ).child(local: "author")
        )
        #expect(author.innerMarkup == "by <a href=\"/author/foobar\">Foo Bar</a>")
        #expect(!author.innerMarkup.contains("<![CDATA["))
    }

    /// A run that is not a CDATA section does not get the marker, even when the element has a child.
    @Test func textRunsAreKeptInOrderWithinTheElement() throws {
        let author = try #require(
            try XMLReader.read(Data("<item><author>a <b>b</b> c</author></item>".utf8)).child(local: "author")
        )
        #expect(author.text == "a  c")
        #expect(author.innerContent == "a b c")
        #expect(author.innerMarkup == "a <b>b</b> c")
    }

    /// An empty element has no content piece, so the inner content is empty and the branch that
    /// checks it falls through to the default.
    @Test func anElementWithNoContentHasNoInnerContent() throws {
        let author = try #require(
            try XMLReader.read(Data("<item><author></author></item>".utf8)).child(local: "author")
        )
        #expect(author.text == "")
        #expect(author.innerMarkup == "")
    }
}
