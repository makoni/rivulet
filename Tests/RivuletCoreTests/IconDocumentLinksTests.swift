import Foundation
import Testing
@testable import RivuletCore

/// Which `link` elements a document offers as the feed icon, read through the same HTML subset
/// the sanitizer uses. Ported from `internal/reader/icon/finder.go`
/// (`findIconURLsFromHTMLDocument`); the upstream cases in `finder_test.go` are named per case.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the four
/// selector branches, and which of them fold case — `apple-touch-icon` is the one that does not,
/// so a patch that folds it fails the case that says so; a `rel` is compared whole, so a patch
/// that compares by prefix fails the case with the trailing space; the href is not
/// whitespace-only; an href the parse cannot read is skipped rather than passed through; a `link`
/// inside a raw-text element is text, not an element; the self-closing token kind is read as an
/// element; the order is document order, not sorted; the resolution rules and the escaped path,
/// which are the URL layer's rules read through the scan; the bytes go through the charset layer,
/// and the pin fails when the charset the content type names is not consulted; and the attribute
/// name is lower-cased and the value is decoded, which are the tokenizer's rules read through the
/// scan.
///
/// What they cannot fail on: the selector's test that the `href` attribute is there at all,
/// because a missing href reads as the empty value and the same guard answers for both; the
/// reference's logging, which this port does not have; the charset detection steps no case here
/// reads (the byte-order mark, the meta prescan, the "looks like UTF-8" answer), which the
/// charset suite pins, and the tokenizer's rules as rules of the tokenizer, which its own suite
/// pins.
@Suite struct IconDocumentLinksTests {
    @Test func theFourSelectorBranchesMatchInDocumentOrder() {
        // Ported from `TestFindIconURLsFromHTMLDocument_MultipleIcons`.
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <link rel="icon" href="/favicon.ico">
                <link rel="shortcut icon" href="/shortcut-favicon.ico">
                <link rel="icon shortcut" href="/icon-shortcut.ico">
                <link rel="apple-touch-icon" href="/apple-touch-icon.png">
            </head>
            </html>
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == [
                "https://example.org/favicon.ico",
                "https://example.org/shortcut-favicon.ico",
                "https://example.org/icon-shortcut.ico",
                "https://example.org/apple-touch-icon.png",
            ])
    }

    @Test func theIconBranchesCompareRelCaseInsensitively() {
        // Ported from `TestFindIconURLsFromHTMLDocument_CaseInsensitiveRel`.
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <link rel="ICON" href="/favicon1.ico">
                <link rel="Icon" href="/favicon2.ico">
                <link rel="SHORTCUT ICON" href="/favicon3.ico">
                <link rel="Shortcut Icon" href="/favicon4.ico">
                <link rel="ICON SHORTCUT" href="/favicon5.ico">
                <link rel="Icon Shortcut" href="favicon6.ico">
            </head>
            </html>
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org/folder/") == [
                "https://example.org/favicon1.ico",
                "https://example.org/favicon2.ico",
                "https://example.org/favicon3.ico",
                "https://example.org/favicon4.ico",
                "https://example.org/favicon5.ico",
                "https://example.org/folder/favicon6.ico",
            ])
    }

    @Test func appleTouchIconIsTheBranchThatDoesNotFoldCase() {
        // The selector writes the `apple-touch-icon` branch without the `i` flag, so this document
        // answers only the lower-cased one. A patch that folds case for every branch answers both.
        let html = """
            <link rel="apple-touch-icon" href="/lower.ico">
            <link rel="APPLE-TOUCH-ICON" href="/upper.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/lower.ico"])
    }

    @Test func aRelThatIsNotOneOfTheFourBranchesIsNotAnIcon() {
        // Ported from `TestFindIconURLsFromHTMLDocument_NoIcons`. A `rel` is compared whole, so a
        // value with an extra space is not the branch either.
        let html = """
            <link rel="stylesheet" href="/style.css">
            <link rel="canonical" href="https://example.com">
            <link rel="icon " href="/spaced.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org").isEmpty)
    }

    @Test func attributeNamesAreComparedLowerCased() {
        let html = #"<link REL="icon" HREF="/upper-case-name.ico">"#
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/upper-case-name.ico"])
    }

    @Test func hrefMustBePresentAndNotWhitespaceOnly() {
        // Ported from `TestFindIconURLsFromHTMLDocument_EmptyHref`.
        let html = """
            <link rel="icon" href="">
            <link rel="icon" href="   ">
            <link rel="icon">
            <link rel="shortcut icon" href="/valid-icon.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/valid-icon.ico"])
    }

    @Test func valuesAreResolvedAgainstTheDocumentURL() {
        // Ported from `TestFindIconURLsFromHTMLDocument_RelativeAndAbsoluteURLs`.
        let html = """
            <link rel="icon" href="/absolute-path.ico">
            <link rel="icon" href="relative-path.ico">
            <link rel="icon" href="../parent-dir.ico">
            <link rel="icon" href="https://example.com/external.ico">
            <link rel="icon" href="//cdn.example.com/protocol-relative.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org/folder/") == [
                "https://example.org/absolute-path.ico",
                "https://example.org/folder/relative-path.ico",
                "https://example.org/parent-dir.ico",
                "https://example.com/external.ico",
                "https://cdn.example.com/protocol-relative.ico",
            ])
    }

    @Test func dataURLsArePassedAsTheyWereRead() {
        // Ported from `TestFindIconURLsFromHTMLDocument_DataURLs`: a data URL is absolute for the
        // parse, so it is returned as it was read, and the scan does not resolve it.
        let svg = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg'></svg>"
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
            + "2mNkYPhfDwAChAGAhGAQ+QAAAABJRU5ErkJggg=="
        let html = """
            <link rel="icon" href="\(png)">
            <link rel="shortcut icon" href="\(svg)">
            <link rel="icon" href="/regular-icon.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org/folder") == [png, svg,
                "https://example.org/regular-icon.ico"])
    }

    @Test func aLinkInsideARawTextElementIsTextNotAnElement() {
        // The tokenizer reads the content of `title` as data, so the markup inside it is not a tag
        // the selector can match.
        let html = """
            <title><link rel="icon" href="/inside-title.ico"></title>
            <link rel="icon" href="/outside.ico">
            """
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/outside.ico"])
    }

    @Test func theSelfClosingTokenKindIsReadAsAnElement() {
        // The tokenizer answers with the self-closing start tag token for `/>`, which
        // the scan must read as an element like any other start tag. Outside foreign
        // content the reference's tree does not acknowledge the flag, and `link` is a
        // void element, so this pins the token kind, not the tree's insertion mode.
        let html = "<link rel=\"icon\" href=\"/self-closing.ico\"/>"
            + " <link rel=\"apple-touch-icon\" href=\"/plain.ico\">"
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == [
                "https://example.org/self-closing.ico",
                "https://example.org/plain.ico",
            ])
    }

    @Test func anHrefTheParseCannotReadIsSkippedNotPassedThrough() {
        // The reference logs a warning and continues, so the document answers only the
        // href it could resolve. The control character is the case the parse table
        // reports.
        let html = "<link rel=\"icon\" href=\"/bad\u{07}char.ico\">"
            + " <link rel=\"icon\" href=\"/good.ico\">"
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/good.ico"])
    }

    @Test func theAttributeValuesAreDecoded() {
        // The tokenizer decodes a character reference in an attribute value, which is
        // what `TagAttr` returns, so the href is read as the decoded value before it is
        // resolved.
        let html = #"<link rel="icon" href="/fav&#105;con.ico">"#
        #expect(IconDocumentLinks.iconURLs(document: Data(html.utf8), contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/favicon.ico"])
    }

    @Test func bytesThatAreNotValidUTF8GoThroughTheCharsetLayer() {
        // The charset layer answers unchanged for bytes that are already valid UTF-8,
        // and this is the case where it cannot: the ISO-8859-1 byte becomes the
        // character it names, which changes the URL the scan writes. The path is written
        // escaped, as Go's `escape(path, encodePath)` does for a byte above ASCII, so
        // the value the pin reads is the escaped one.
        var bytes = Data("<link rel=\"icon\" href=\"/f".utf8)
        bytes.append(0xE9)
        bytes.append(Data("avicon.ico\">".utf8))
        #expect(IconDocumentLinks.iconURLs(document: bytes,
            contentType: "text/html; charset=iso-8859-1", documentURL: "https://example.org")
            == ["https://example.org/f%C3%A9avicon.ico"])
    }
}
