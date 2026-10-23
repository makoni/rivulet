import Foundation
import Testing
@testable import RivuletCore

/// Charset behavior pinned by the ported Miniflux fixtures.
///
/// Every test mirrors an upstream assertion, including the upstream validity check; the upstream
/// test name is given in a comment. Upstream tests live in
/// `internal/reader/encoding/encoding_test.go`.
@Suite struct CharsetFixtureTests {
    // MARK: - XML documents decoded by their prolog label

    /// `TestCharsetReaderWithUTF8`
    @Test func utf8DocumentIsReturnedUnchanged() throws {
        let data = try Fixtures.data("encoding/utf8.xml")
        let decoded = try FeedCharset.decode(data, label: "UTF-8")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestCharsetReaderWithISO88591`
    @Test func iso88591DocumentIsConvertedToUTF8() throws {
        let data = try Fixtures.data("encoding/iso-8859-1.xml")
        let decoded = try FeedCharset.decode(data, label: "ISO-8859-1")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestCharsetReaderWithWindows1252`
    @Test func windows1252DocumentIsConvertedToUTF8() throws {
        let data = try Fixtures.data("encoding/windows-1252.xml")
        let decoded = try FeedCharset.decode(data, label: "windows-1252")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Euro €"))
    }

    /// `TestCharsetReaderWithInvalidProlog`: the prolog says `encoding="invalid"`, but the
    /// document is valid UTF-8, so the label is never consulted and no error is raised.
    @Test func unknownLabelIsIgnoredForValidUTF8() throws {
        let data = try Fixtures.data("encoding/invalid-prolog.xml")
        let decoded = try FeedCharset.decode(data, label: "invalid")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestCharsetReaderWithUTF8DocumentWithIncorrectProlog`: valid UTF-8 bytes win over a
    /// prolog that claims ISO-8859-1; the Korean title survives instead of turning into
    /// mojibake, which is the observable difference from decoding the bytes as ISO-8859-1.
    @Test func utf8BytesWinOverAnIncorrectProlog() throws {
        let data = try Fixtures.data("encoding/utf8-incorrect-prolog.xml")
        let decoded = try FeedCharset.decode(data, label: "ISO-8859-1")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
        #expect(Fixtures.utf8(decoded).contains("테스트 피드"))
    }

    /// `TestCharsetReaderWithWindows1252DocumentWithIncorrectProlog`: the file holds UTF-8
    /// bytes but claims windows-1252; the bytes win again.
    @Test func utf8BytesWinOverAWindows1252Prolog() throws {
        let data = try Fixtures.data("encoding/windows-1252-incorrect-prolog.xml")
        let decoded = try FeedCharset.decode(data, label: "windows-1252")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Euro €"))
    }

    /// `TestCharsetReaderWithKOI8RFeedFixture`
    @Test func koi8rFeedIsConvertedToUTF8() throws {
        let data = try Fixtures.data("encoding/koi8r.xml")
        let decoded = try FeedCharset.decode(data, label: "KOI8-R")
        #expect(Fixtures.isValidUTF8(decoded))
        let text = Fixtures.utf8(decoded)
        #expect(text.contains("Пример RSS ленты"))
        #expect(text.contains("Привет мир! Ёжик, чай, Москва, Санкт-Петербург."))
    }

    // MARK: - HTML documents decoded by content type and detection

    /// `TestNewReaderWithUTF8Document`
    @Test func utf8HTMLWithContentTypeCharset() throws {
        let data = try Fixtures.data("encoding/utf8.html")
        let decoded = FeedCharset.decode(data, contentType: "text/html; charset=UTF-8")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewReaderWithUTF8DocumentAndNoContentEncoding`
    @Test func utf8HTMLWithoutContentTypeCharset() throws {
        let data = try Fixtures.data("encoding/utf8.html")
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewReaderWithISO88591Document`
    @Test func iso88591XMLWithContentTypeCharset() throws {
        let data = try Fixtures.data("encoding/iso-8859-1.xml")
        let decoded = FeedCharset.decode(data, contentType: "text/html; charset=ISO-8859-1")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewReaderWithISO88591DocumentAndNoContentType`: no BOM, no content-type charset
    /// and no `<meta>` in the document, so the `windows-1252` default decodes it.
    @Test func iso88591XMLWithoutAnyDeclaredEncoding() throws {
        let data = try Fixtures.data("encoding/iso-8859-1.xml")
        let decoded = FeedCharset.decode(data, contentType: "")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewReaderWithISO88591DocumentWithMetaAfter1024Bytes`: the `<meta>` sits past the
    /// 1024-byte detection window, so detection falls through to the default — which still
    /// decodes this document, because ISO-8859-1 and windows-1252 agree on its bytes.
    @Test func metaCharsetAfterTheDetectionWindow() throws {
        let data = try Fixtures.data("encoding/iso-8859-1-meta-after-1024.html")
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewReaderWithUTF8DocumentWithMetaAfter1024Bytes`
    @Test func utf8MetaCharsetAfterTheDetectionWindow() throws {
        let data = try Fixtures.data("encoding/utf8-meta-after-1024.html")
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded).contains("Café"))
    }

    /// `TestNewCharsetReaderWithKOI8RFeedFixtureAndContentType`
    @Test func koi8rFeedWithContentTypeCharset() throws {
        let data = try Fixtures.data("encoding/koi8r.xml")
        let decoded = FeedCharset.decode(data, contentType: "application/rss+xml; charset=KOI8-R")
        #expect(Fixtures.isValidUTF8(decoded))
        let text = Fixtures.utf8(decoded)
        #expect(text.contains("Тестовая лента в кодировке KOI8-R"))
        #expect(text.contains("Проверка специальных символов"))
    }
}
