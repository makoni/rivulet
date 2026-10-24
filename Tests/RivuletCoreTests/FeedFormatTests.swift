import Foundation
import Testing
@testable import RivuletCore

/// Feed-format detection. Ported from Miniflux `internal/reader/parser/format.go`; the tests that
/// mirror an upstream assertion name the upstream test (`format_test.go`).
///
/// Detection reads tokens through the same tolerant reader the parser uses, and a tokenizing
/// failure ends the scan rather than failing the call — the reference ignores the error and breaks,
/// so the answer is `unknown` — with one exception: JSON is recognized before any XML token is
/// read.
@Suite struct FeedFormatTests {
    // MARK: - Ported upstream cases

    /// `TestDetectRDF`
    @Test func rdfRootIsDetected() {
        let document = "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999-02-22-rdf-syntax-ns#\""
            + " xmlns=\"http://my.netscape.com/rdf/simple/0.9/\"></rdf:RDF>"
        #expect(FeedFormatDetector.detect(Data(document.utf8)).format == .rdf)
    }

    /// `TestDetectRSS`
    @Test func rssRootIsDetected() {
        let data = Data("<?xml version=\"1.0\"?><rss version=\"2.0\"><channel></channel></rss>".utf8)
        #expect(FeedFormatDetector.detect(data).format == .rss)
    }

    /// `TestDetectAtom10`
    @Test func atomRootWithoutVersionIsAtom10() {
        let atom = "<?xml version=\"1.0\" encoding=\"utf-8\"?><feed xmlns=\"http://www.w3.org/2005/Atom\">"
        let detected = FeedFormatDetector.detect(Data(atom.utf8))
        #expect(detected.format == .atom)
        #expect(detected.version == "1.0")
    }

    /// `TestDetectAtom03`
    @Test func atomRootWithVersion03IsReportedWithItsVersion() {
        let atom = "<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
        #expect(FeedFormatDetector.detect(Data(atom.utf8)).format == .atom)
        #expect(FeedFormatDetector.detect(Data(atom.utf8)).version == "0.3")
    }

    /// `TestDetectAtomWithISOCharset`
    @Test func atomBehindANonUTF8PrologIsStillDetected() {
        let atom = "<?xml version=\"1.0\" encoding=\"ISO-8859-15\"?><feed xmlns=\"http://www.w3.org/2005/Atom\">"
        #expect(FeedFormatDetector.detect(Data(atom.utf8)).format == .atom)
    }

    /// `TestDetectJSON`
    @Test func jsonDocumentIsDetectedBeforeAnyXMLTokenIsRead() {
        let json = "\n\t{\n\t\t\"version\" : \"https://jsonfeed.org/version/1\",\n\t\t\"title\" : \"Example\"\n\t}\n"
        #expect(FeedFormatDetector.detect(Data(json.utf8)).format == .json)
    }

    /// `TestDetectUnknown`
    @Test func htmlDocumentIsNotAFeed() {
        let html = "\n\t<!DOCTYPE html> <html> </html>\n\t"
        #expect(FeedFormatDetector.detect(Data(html.utf8)).format == .unknown)
    }

    /// `TestDetectJSONWithLargeLeadingWhitespace`
    @Test func jsonAfterALargeRunOfWhitespaceIsDetected() {
        let document = String(repeating: " ", count: 10000) + "{\"version\" : \"1\"}"
        #expect(FeedFormatDetector.detect(Data(document.utf8)).format == .json)
    }

    /// `TestDetectJSONWithMixedWhitespace`
    @Test func jsonAfterMixedWhitespaceIsDetected() {
        let document = String(repeating: "\n\t  ", count: 10000) + "{\"version\" : \"1\"}"
        #expect(FeedFormatDetector.detect(Data(document.utf8)).format == .json)
    }

    /// `TestDetectOnlyWhitespace`
    @Test func documentOfOnlyWhitespaceIsNotAFeed() {
        let document = String(repeating: " \t\n\r", count: 10000)
        #expect(FeedFormatDetector.detect(Data(document.utf8)).format == .unknown)
    }

    /// `TestDetectJSONSmallerThanBuffer` — the reference reads a 32-byte buffer; a shorter document
    /// is still decided by its first non-whitespace character.
    @Test func shortJSONDocumentIsDetected() {
        #expect(FeedFormatDetector.detect(Data("{\"version\":\"1\"}".utf8)).format == .json)
    }

    /// `TestDetectJSONWithWhitespaceSmallerThanBuffer`
    @Test func shortJSONDocumentAfterWhitespaceIsDetected() {
        #expect(FeedFormatDetector.detect(Data("  {\"title\":\"test\"}  ".utf8)).format == .json)
    }

    // MARK: - Details the reference does not test

    @Test func byteAboveASCIIThatIsSpaceCountsAsWhitespace() {
        // Go reads the buffer as runes, so bytes 0x85 (NEL) and 0xA0 (NBSP) are whitespace there; a
        // byte such as 0x81 is not, and decides the answer.
        #expect(FeedFormatDetector.detect(Data([0xA0, 0x7B, 0x7D])).format == .json)
        #expect(FeedFormatDetector.detect(Data([0x85, 0x7B, 0x7D])).format == .json)
        #expect(FeedFormatDetector.detect(Data([0x81, 0x7B, 0x7D])).format == .unknown)
    }

    @Test func scanStopsAtTheFiftiethToken() {
        // 49 comments put the root at token 50, which is still read; 50 comments put it at 51,
        // which is past the cap, so the format is unknown.
        let atTheCap = String(repeating: "<!-- x -->", count: 49) + "<rss></rss>"
        let pastTheCap = String(repeating: "<!-- x -->", count: 50) + "<rss></rss>"
        #expect(FeedFormatDetector.detect(Data(atTheCap.utf8)).format == .rss)
        #expect(FeedFormatDetector.detect(Data(pastTheCap.utf8)).format == .unknown)
    }

    @Test func tokenizingFailureEndsTheScanWithoutFailingDetection() {
        #expect(FeedFormatDetector.detect(Data("<note>a ]]></note>".utf8)).format == .unknown)
    }

    @Test func rootsAreMatchedOnTheirLocalNameOnly() {
        // The reference matches `Name.Local`, so a prefixed root element is decided by its local
        // name, as `rdf:RDF` is in `TestDetectRDF`.
        #expect(FeedFormatDetector.detect(Data("<x><feed></feed></x>".utf8)).format == .atom)
    }

    @Test func versionAttributeOnlyCountsForAtom() {
        // `version="0.3"` on an rss root is not an Atom version, which is what the reference's
        // switch shape shows.
        #expect(FeedFormatDetector.detect(Data("<rss version=\"0.3\"></rss>".utf8)).version == nil)
    }
}
