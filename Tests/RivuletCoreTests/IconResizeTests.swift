import Foundation
import Testing
@testable import RivuletCore

/// `resizeIcon` of `internal/reader/icon/finder.go` at `c4d54f87`, read as pure logic.

/// The rules are the reference's: the content type is compared as the whole value it was read with,
/// the four types of the switch are the only ones that reach the read, the dimensions come from the
/// file's own magic rather than from the declared type, the WebP match names the bytes up to the
/// chunk name so all three chunk shapes are read, the start-of-frame segment is read only for the
/// three markers the walk dispatches and only for the shapes `processSOF` accepts, the GIF read
/// takes the 13 bytes of its own header before it answers the logical screen, a header the read
/// cannot answer leaves the bytes as they were, a side strictly greater than 4096 or a pixel count
/// greater than 4096×4096 is the rejection the search continues past, a file at or under 32×32 is
/// left as it is, and anything else becomes a 32×32 PNG with the content type written as the
/// literal `image/png`. The checksum is the value the bytes as read produced, because
/// `downloadIcon` computes it before calling the resize, so the hash and the content stop
/// corresponding for a resized icon.

/// What these pins can fail on, each checked by patching the rule and reverting (17 pins, 25
/// probes): the whole-value comparison — 1 probe, a patch that normalizes the content type before
/// the pipeline reads it fails on `image/png; charset=x`; the type list read before the read — 1
/// probe, a patch that reads the header and its rejection first; the magic match — 1 probe, a patch
/// that matches on the declared type fails where the declared type and the file's own format part;
/// the per-magic length — 1 probe, a patch that compares every magic at one fixed header length
/// fails on the file shorter than the longest magic; the start-of-frame rules — 5 probes, one that
/// accepts only the first of the three markers, one that dispatches the whole group instead of the
/// three, one that accepts any component count, one that drops the precision rule, and one that
/// drops the rule that the count byte matches the length; the header length the GIF read takes — 1
/// probe, a patch that lowers the 13 bytes to 10, which is the file the pin names; the WebP chunk
/// shapes — 4 probes, a patch that matches only the lossy chunk name fails the packed case, one
/// that reads the packed pair as 16-bit fails that case, one that drops the plus one fails the
/// extended case, and one that reads the lossy pair at the start of the chunk instead of after its
/// sync code fails that case; the key-frame bit — 1 probe, a patch that reads the dimensions
/// whatever the frame tag says; the segment walk — 1 probe, a patch that assumes the frame segment
/// is the first one; the header the read cannot answer — 1 probe, a patch that answers dimensions
/// for a file no magic matches; the dimension guard — 2 probes, one that reads only one side and
/// one that compares as greater-or-equal instead of strictly greater; the passthrough guard — 3
/// probes, one that reads only the height, one that reads only the width, and one that compares as
/// less instead of less-or-equal, which is why the pin holds a case in each direction; the document
/// the resize writes — 1 probe, a patch that writes it at the source dimensions; the checksum — 1
/// probe, a patch that recomputes it from the resized bytes; and the pixels read through the
/// declared type — 1 probe, a patch that dispatches the decode by the file's own format.

/// What these pins cannot show: the SVG branch, which the reference minifies and this port has no
/// minifier for, so no patch can part the branch from the type list it sits before; the content
/// type the document writes, because the only bytes this port's decoder can read are bytes the name
/// already calls `image/png`, so no input can part the literal from the declared type; the pixel
/// count term, which no patch can flip because a side above 4096 answers before the count is read,
/// which is why the upstream test that names "too large pixel count" is kept as the case the
/// dimension term answers; the guard that a dimension the read answers as zero ends the resize,
/// because the only file that can answer zero is the file the key-frame pin reads, and dropping
/// that guard answers the same bytes for it; which pixels the scale produces, because
/// `draw.BiLinear` answers its own values and this port names its own, so the pins read the
/// dimensions and the content type of the document rather than its bytes; the encode failure, which
/// no input can make the encoder answer; and the pixel decode for GIF and WebP, which this port has
/// no decoder for, so those cases read only that the guard passes the bytes on — the reference
/// resizes both, which `docs/parity.md` records.

@Suite struct IconResizeTests {
    @Test func contentTypesComparedAsTheWholeValue() {
        let original = IconTestBytes.pngDecodable(width: 33, height: 33)
        let answer = IconResize.resize(IconCandidate(mimeType: "image/png; charset=x", content: original))
        #expect(answer?.content == original, "a content type carrying a parameter is not one of the four")
        #expect(answer?.mimeType == "image/png; charset=x")
    }

    @Test func theTypeListIsReadBeforeTheReadAndItsRejection() {
        // The list runs before the read, so a file the read would reject is passed on when the name
        // is not one of the four: a patch that reads the header first answers the rejection for it.
        let original = IconTestBytes.pngHeaderOnly(width: 4097, height: 7)
        let answer = IconResize.resize(IconCandidate(mimeType: "image/x-icon", content: original))
        #expect(answer?.content == original, "a type the switch does not have is skipped before the read")
    }

    @Test func theDimensionsComeFromTheFilesOwnMagic() {
        let answer = IconResize.resize(IconCandidate(mimeType: "image/gif",
            content: IconTestBytes.pngHeaderOnly(width: 7, height: 4097)))
        #expect(answer == nil, "the read matches by magic, so the PNG header is read for a GIF name")
    }

    @Test func aFileShorterThanTheLongestMagicIsReadByItsOwnMagic() {
        // The GIF magic is 6 bytes and the WebP magic is 15, so this 13-byte file is long enough
        // for its own magic: a patch that compares every magic against one fixed 17-byte header
        // stops reading it.
        #expect(IconResize.resize(IconCandidate(mimeType: "image/gif",
            content: IconTestBytes.gif(width: 7, height: 4097))) == nil,
            "the read peeks the length of its own magic, not a fixed header")
    }

    @Test func eachWebPChunkShapeAnswersItsOwnDimensions() throws {
        let extended = try #require(IconImageHeader.dimensions(
            of: [UInt8](IconTestBytes.webpVP8X(width: 33, height: 32))))
        #expect(extended.width == 33 && extended.height == 32,
            "the extended chunk stores the canvas as the value plus one")

        let packed = try #require(IconImageHeader.dimensions(
            of: [UInt8](IconTestBytes.webpVP8L(width: 41, height: 37))))
        #expect(packed.width == 41 && packed.height == 37,
            "the packed chunk stores it as two 14-bit values, each plus one")

        let lossy = try #require(IconImageHeader.dimensions(
            of: [UInt8](IconTestBytes.webpVP8(width: 45, height: 31))))
        #expect(lossy.width == 45 && lossy.height == 31,
            "the lossy chunk answers the pair after its sync code, not as the stored value plus one")
    }

    @Test func theLossyShapeReadsItsFrameHeaderOnlyForAKeyFrame() throws {
        let dimensions = try #require(IconImageHeader.dimensions(
            of: [UInt8](IconTestBytes.webpVP8(width: 45, height: 31, keyFrame: false))))
        #expect(dimensions.width == 0 && dimensions.height == 0,
            "a frame that is not a key frame has no header to read, which is the zero the read answers")
    }

    @Test func theStartOfFrameSegmentIsFoundByWalkingTheSegments() {
        // A table segment before the frame segment: the walk has to pass it to read the dimensions,
        // so a patch that assumes the frame is the first segment answers nothing for this file.
        #expect(IconResize.resize(IconCandidate(mimeType: "image/jpeg",
            content: IconTestBytes.jpeg(width: 7, height: 4097, tableSegment: true))) == nil,
            "the dimensions the walk answers are the frame segment's, not the first segment's")
    }

    @Test func theSOFReadTakesOnlyTheShapesGoProcessSOFReads() throws {
        // The walk dispatches `processSOF` for three markers, and the shape rules are its own: the
        // length names the header plus one triple per component, the component count is one of the
        // three values it accepts, the precision is the one value it accepts, and the count byte
        // must match the length. Each case writes one of those wrong, so its answer names the rule,
        // and each is a single-segment file, so a patch on the walk cannot change its answer.
        let accepted = try #require(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.jpeg(marker: 0xC1, width: 33, height: 32))))
        #expect(accepted.width == 33 && accepted.height == 32,
            "the second of the three markers the walk dispatches is read")
        #expect(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.jpeg(marker: 0xC9, width: 33, height: 32))) == nil,
            "a marker the walk does not dispatch is passed over, not read as a frame")
        #expect(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.jpeg(count: 2, width: 33, height: 32))) == nil,
            "a length naming two triples is not one of the three counts the rule accepts")
        #expect(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.jpeg(precision: 12, width: 33, height: 32))) == nil,
            "the precision is the one value the rule accepts")
        #expect(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.jpeg(count: 1, length: 17, width: 33, height: 32))) == nil,
            "a count byte that does not match the length is the error the read reports")
    }

    @Test func aFileTooShortForItsOwnHeaderIsTheErrorTheReadReports() {
        // `readHeaderAndScreenDescriptor` reads 13 bytes before it answers the logical screen, so a
        // 12-byte GIF is the error the read reports and the resize passes the bytes on. The 13-byte
        // file the per-magic-length pin reads is the other side of that boundary.
        #expect(IconImageHeader.dimensions(of: [UInt8](
            IconTestBytes.gif(width: 7, height: 4097, length: 12))) == nil,
            "the header read is 13 bytes, not the 10 the dimensions sit inside")
    }

    @Test func aHeaderTheReadCannotAnswerLeavesTheBytesAsTheyWere() {
        let original = Data("invalid data".utf8)
        let answer = IconResize.resize(IconCandidate(mimeType: "image/png", content: original))
        #expect(answer?.content == original, "the upstream case that names a file no decoder reads")
    }

    @Test func aSideStrictlyGreaterIsTheRejection() {
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png",
            content: IconTestBytes.pngHeaderOnly(width: 4097, height: 7))) == nil,
            "the guard reads both sides and compares as strictly greater")
        let atTheBoundary = IconTestBytes.pngHeaderOnly(width: 4096, height: 7)
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png", content: atTheBoundary))?.content ==
            atTheBoundary, "4096 on one side is not the rejection")
    }

    @Test func thePixelCountCaseIsAnsweredByTheDimensionTerm() {
        // The upstream test names this case "too large pixel count", and this port answers the same
        // rejection, but through the dimension term: no patch that removes the count term changes
        // the answer, so the pin records the case rather than the term.
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png",
            content: IconTestBytes.pngHeaderOnly(width: 4096, height: 4097))) == nil,
            "the count is read, but the dimension term answers first for every input that reaches it")
    }

    @Test func aFileAtOrUnder32x32IsLeftAsItIs() {
        let original = IconTestBytes.pngDecodable(width: 32, height: 32)
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png", content: original))?.content ==
            original, "the guard compares as less-or-equal")
    }

    @Test func thePassthroughGuardReadsBothSides() {
        // Both sides are read: the first file has the height at 32 with the width above it and the
        // second the width at 32 with the height above it, so a patch that reads one side fails.
        let overTheWidth = IconTestBytes.pngDecodable(width: 33, height: 32)
        let overTheHeight = IconTestBytes.pngDecodable(width: 32, height: 33)
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png", content: overTheWidth))?.content
            != overTheWidth, "one side above 32 is enough to reach the scale")
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png", content: overTheHeight))?.content
            != overTheHeight, "and the other side is read too")
        #expect(IconResize.resize(IconCandidate(mimeType: "image/png", content: overTheWidth))?.mimeType
            == "image/png")
    }

    @Test func theResizeWritesAPngAt32x32() throws {
        let original = IconTestBytes.pngDecodable(width: 33, height: 33)
        let answer = try #require(IconResize.resize(IconCandidate(mimeType: "image/png", content: original)))
        let dimensions = try #require(IconImageHeader.dimensions(of: [UInt8](answer.content)))
        #expect(dimensions.width == 32 && dimensions.height == 32, "the document is written at 32×32")
        #expect(answer.mimeType == "image/png", "the content type is the literal the reference writes")
        #expect(answer.content != original)
    }

    @Test func theChecksumIsTheValueTheBytesAsReadProduced() throws {
        let original = IconTestBytes.pngDecodable(width: 33, height: 33)
        let answer = try #require(IconResize.resize(IconCandidate(mimeType: "image/png", content: original)))
        #expect(answer.hash == Hashes.sha256(original), "downloadIcon hashes before it resizes")
    }

    @Test func thePixelsAreReadThroughTheDeclaredType() {
        // The bytes are a PNG the decoder here can read, but the name says GIF, which this port has
        // no decoder for, so the case that parts the two answers with the bytes as they were.
        let original = IconTestBytes.pngDecodable(width: 33, height: 33)
        let answer = IconResize.resize(IconCandidate(mimeType: "image/gif", content: original))
        #expect(answer?.content == original,
            "the dimensions are read through the magic, the pixels through the declared type")
    }
}
