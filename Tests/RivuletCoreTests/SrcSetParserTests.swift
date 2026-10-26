import Foundation
import Testing
@testable import RivuletCore

/// The srcset attribute parser, ported from Miniflux `internal/reader/sanitizer/srcset.go`, which
/// follows the WebKit `HTMLSrcsetParser` behaviour and the WHATWG "parse a srcset attribute" rules.
///
/// A candidate is a URL up to the first ASCII whitespace, then its descriptors. The descriptors are
/// serialized in the reference's order: density first, then width, and a height-only descriptor is
/// not a candidate at all.
@Suite struct SrcSetParserTests {
    private func assertCandidates(_ input: String, _ expectedCount: Int, _ expectedString: String) {
        let candidates = SrcSetParser.parse(input)
        #expect(candidates.count == expectedCount, "candidate count for \(input)")
        #expect(candidates.map(\.description).joined(separator: ", ") == expectedString, Comment(rawValue: input))
    }

    /// `TestParseSrcSetAttributeValidCandidates`
    @Test(arguments: [
        (
            "example-320w.jpg, example-480w.jpg 1.5x,   example-640,w.jpg 2x, example-640w.jpg 640w",
            4,
            "example-320w.jpg, example-480w.jpg 1.5x, example-640,w.jpg 2x, example-640w.jpg 640w"
        ),
        ("a.png 1x,b.png 2x", 2, "a.png 1x, b.png 2x"),
        ("  a.png   1x  ,   b.png    2x   ", 2, "a.png 1x, b.png 2x"),
        (
            "http://example.org/example-320w.jpg 320w, http://example.org/example-480w.jpg 1.5x",
            2,
            "http://example.org/example-320w.jpg 320w, http://example.org/example-480w.jpg 1.5x"
        ),
        (
            "http://example.org/example-320w.jpg 320w,http://example.org/example-480w.jpg 1.5x",
            2,
            "http://example.org/example-320w.jpg 320w, http://example.org/example-480w.jpg 1.5x"
        ),
        (
            "http://example.org/example-320w.jpg 320w, http://example.org/example-480w.jpg 1.5x, ",
            2,
            "http://example.org/example-320w.jpg 320w, http://example.org/example-480w.jpg 1.5x"
        ),
        ("http://example.org/example-320w.jpg", 1, "http://example.org/example-320w.jpg"),
        (
            "http://example.org/example,a:b/d.jpg , example-480w.jpg 1.5x",
            2,
            "http://example.org/example,a:b/d.jpg, example-480w.jpg 1.5x"
        ),
        ("http://example.org/example-320w.jpg 320w 240h", 1, "http://example.org/example-320w.jpg 320w"),
        (
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA 1x, image@2x.png 2x",
            2,
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA 1x, image@2x.png 2x"
        ),
        ("http://example.org/example(1).jpg 1x", 1, "http://example.org/example(1).jpg 1x"),
    ]) func validCandidate(input: String, expectedCount: Int, expectedString: String) {
        assertCandidates(input, expectedCount, expectedString)
    }

    /// `TestParseSrcSetAttributeInvalidCandidates`
    @Test(arguments: [
        "",
        "http://example.org/example-320w.jpg test",
        "http://example.org/example-320w.jpg 10w 1x",
        "http://example.org/example-320w.jpg 20h",
        "http://example.org/example-320w.jpg +1x",
        "http://example.org/example-320w.jpg 1.x",
        "http://example.org/example-320w.jpg -1x",
        "http://example.org/example-320w.jpg 0w",
        "http://example.org/example-320w.jpg -10w",
        "http://example.org/example-320w.jpg 10.5w",
        "http://example.org/example-320w.jpg (1x)",
        "http://example.org/example-320w.jpg calc(1x, 2x)",
    ]) func invalidCandidateIsNotACandidate(input: String) {
        assertCandidates(input, 0, "")
    }

    /// The descriptor serialization the reference formats with `strconv.FormatFloat(…, 'g', -1,
    /// 64)`, which is what the density round-trip below pins.
    @Test func densityIsSerializedWithoutTrailingZeros() {
        #expect(SrcSetParser.parse("a.png 1.50x").map(\.description).joined(separator: ", ") == "a.png 1.5x")
        #expect(SrcSetParser.parse("a.png 2.0x").map(\.description).joined(separator: ", ") == "a.png 2x")
    }
}
