import Foundation
import Testing
@testable import RivuletCore

/// The `data:` URL an icon document can offer, ported from `internal/reader/icon/finder.go`
/// (`parseImageDataURL`); the upstream cases in `finder_test.go` are named per case.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the mediatype is
/// mandatory and has to name an image — a patch that accepts any mediatype fails the two cases
/// that report it, and one that drops the `image/` requirement fails the `text/plain` one; the
/// encoding is one of `base64`, `utf8` or the empty string, so a patch that reads an unknown
/// encoding fails the `base32` case; the three encodings do three different things, and a patch
/// that makes them the same fails the cases that tell them apart; data is required, so a patch
/// that lets it be empty fails the case that reports it; and the URL-decoding branch is Go's
/// `QueryUnescape`, which turns a `+` into a space and refuses a truncated escape.
///
/// What they cannot fail on: the hash, which is the same SHA-256 the reader computes everywhere
/// and is pinned by `HashTests`; the reference's error wording, which this port keeps as typed
/// cases; and the `data:` prefix as a rule of its own, because a value that does not start with
/// it fails on the same shape check as a mediatype that is not an image.
@Suite struct IconDataURLTests {
    @Test func base64EncodingIsDecoded() throws {
        // Ported from `TestParseImageDataURL`. The content is the decoded bytes, and the hash is
        // SHA-256 of them, which is the reference's value for this input.
        let parsed = try IconDataURL.parse("data:image/png;base64,"
            + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
            + "2mNkYPhfDwAChAGAhGAQ+QAAAABJRU5ErkJggg==")
        #expect(parsed.mimeType == "image/png")
        #expect(parsed.content.prefix(4) == Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(parsed.content.count == 70)
        #expect(parsed.hash == "3a484817483e985f26a0cf76b46a160826d301d26048c76ef908332eadc0e837")
    }

    @Test func noEncodingMeansURLDecoded() throws {
        // Ported from `TestParseImageDataURLWithNoEncoding`: the value is URL-decoded,
        // so it is not the characters as they were written.
        let parsed = try IconDataURL.parse("data:image/webp,%3Ch1%3EHello%2C%20World%21%3C%2Fh1%3E")
        #expect(parsed.mimeType == "image/webp")
        #expect(parsed.content == Data("<h1>Hello, World!</h1>".utf8))
        #expect(parsed.hash == "0ad295df697b9d8baa1bd2146e928d54ef36284963d0e267cb6bbbfbf4c4d3b1")
    }

    @Test func utf8EncodingKeepsTheBytesAsTheyWereRead() throws {
        // Ported from `TestParseImageWithRawSVGEncodedInUTF8`.
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 456 456'>"
            + "<circle></circle></svg>"
        let parsed = try IconDataURL.parse("data:image/svg+xml;utf8,\(svg)")
        #expect(parsed.mimeType == "image/svg+xml")
        #expect(parsed.content == Data(svg.utf8))
        #expect(parsed.hash == "8043d16c73aa216c01ad17cfd49dd211ff690e2782d7c5669cb74e8515a63789")
    }

    @Test(arguments: [
        "data:,Hello%2C%20World%21",
        "data:text/plain;base64,blob",
        "data:image/png",
        "data,test",
        "data:image/png;x,abc",
    ]) func casesThatStopAtTheShapeOfTheValue(input: String) throws {
        // Ported from `TestParseImageDataURLWithNoMediaTypeAndNoEncoding`,
        // `TestParseInvalidImageDataURLWithBadMimeType`, `TestParseInvalidImageDataURL` and
        // `TestParseInvalidImageDataURLWithWrongPrefix`. The mediatype production stops
        // at `;` and `,`, so `image/png;x` is not a mediatype and the encoding branch
        // then sees `x`, which is not one of the three.
        #expect(parseError(input) == .malformed(input))
    }

    @Test func dataIsRequired() throws {
        // Ported from `TestParseInvalidImageDataURLWithNoData`. The reference calls this
        // invalid encoded data, and it reaches that through the shape rule, because the
        // data part must not be empty.
        #expect(parseError("data:image/png;base64,") == .malformed("data:image/png;base64,"))
    }

    @Test func onlyTheThreeEncodingsAreAccepted() throws {
        // Ported from `TestParseInvalidImageDataURLWithUnsupportedEncoding`.
        #expect(parseError("data:image/png;base32,blob")
            == .malformed("data:image/png;base32,blob"))
    }

    @Test func base64ThatCannotBeDecodedIsAnError() throws {
        // The shape is right here, so this is the decode branch: `a==` is not standard-
        // alphabet base64.
        #expect(parseError("data:image/png;base64,a==") == .invalidBase64("a=="))
    }

    @Test func anEscapeThatCannotBeUnescapedIsAnError() throws {
        // The empty-encoding branch is Go's `QueryUnescape`, which refuses a truncated
        // escape instead of writing the characters as they were read.
        #expect(parseError("data:image/png,%A0%") == .invalidEscape("%A0%"))
    }

    @Test func theUnescapedBranchTurnsAPintoASpaceButTheUTF8BranchDoesNot() throws {
        // Go's `QueryUnescape` replaces `+` with a space, which is the one thing the three encoding
        // branches do differently from each other on the same bytes.
        #expect(try IconDataURL.parse("data:image/png,a+b").content == Data("a b".utf8))
        #expect(try IconDataURL.parse("data:image/png;utf8,a+b").content == Data("a+b".utf8))
    }

    /// Reads the branch the reference reports, not its message.
    private func parseError(_ input: String) -> IconDataURLError? {
        do {
            _ = try IconDataURL.parse(input)
            return nil
        } catch let error as IconDataURLError {
            return error
        } catch {
            return nil
        }
    }
}
