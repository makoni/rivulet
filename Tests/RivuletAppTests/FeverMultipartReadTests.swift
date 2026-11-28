import Testing
@testable import RivuletApp

/// The form read the Fever path reads through `r.FormValue`, ported from Go's
/// `Request.ParseMultipartForm` as `internal/fever/middleware.go` uses it at `c4d54f87`. The
/// answers are the reference's own for these inputs, read by a program that ran the same read at
/// the toolchain `go.mod` pins.
///
/// This read has no error half, and that is a rule of its own: `FormValue` discards what
/// `ParseMultipartForm` reports, so a body this read cannot read answers the empty value, and the
/// guard that reads `api_key` sees nothing rather than a failure. What the pins can fail on, each
/// checked by patching the rule and reverting: the media type is read as
/// `mime.ParseMediaType` reads it and compared lowercased — one that compared the content
/// type as it was written fails on `Multipart/Form-Data`, one that accepted any multipart media
/// fails on `multipart/mixed`; the parameter rules — for a pair with no `=`, for a value
/// that is empty as written, for a trailing semicolon that is not the error, and for the media type
/// surviving that error on the urlencoded half; the boundary has to be a parameter of the content
/// type — a patch that fell back to its own boundary fails on it; a part that cannot be
/// read ends the whole body read, so the parts read before the failure are not read either; the three
/// guards of the part loop — disposition, name, and the filename
/// parameter being empty rather than present; a header line with no colon ends the read;
/// the part value is the bytes as written, which a patch that applied the percent-decoding rule
/// fails on, and a line ending can be a bare `LF`, which a patch that required `CRLF` fails on; the
/// order per name is the urlencoded body pairs, then the query pairs, then the
/// parts, with the method deciding whether an urlencoded body is read at all; and the
/// part that declares `Content-Transfer-Encoding: quoted-printable` is decoded as
/// `mime/quotedprintable` reads it — one that skipped the decoder, one each for the name
/// compared without case, the value compared without case, the first value with the name, the
/// whitespace `trim` takes from the end of the header line and an empty value, one for a part with
/// no name being skipped before the copy, one for a named file part reaching the decoder, one for
/// the lowercase hex, one for the literal `=`, one each for the break on `CRLF` and on a bare `LF`,
/// one for the whitespace between the break and the line ending, one for the break at the end of the
/// part, one for the break needing something before it, one for the line ending inside the part
/// surviving, one each for the control byte, the byte at `0x7F` and the byte at or above `0x80`, and
/// one for the tab that is not a break.
///
/// What these pins cannot show: Go's 10 MB memory threshold and its 1000-part cap, which no input
/// here reaches; the `filename` value as `filepath.Base` cuts it, which only the file half uses and
/// this read never reads; the error values `FormValue` discards, which nothing can be asserted
/// about a read that reports none; and the order of the names, which Go reads through a map and
/// does not fix, so every pin here reads one name at a time. The pin that reads the encoding on the
/// line before the disposition has no patch of its own: the port reads the encoding whatever line it
/// comes on, so the only patch that made it fail was the one that skipped the decoder. The
/// `Header.Del` that follows the comparison is not a rule here, because nothing reads the name after
/// it. The urlencoded body half itself is pinned by `GoogleReaderAuthTests`; the pair rules shared
/// with the query read are pinned by `GoogleReaderQueryTests`, and this read answers them the same
/// way, as `r.Form` ends up holding them.
@Suite struct FeverMultipartReadTests {
    @Test func theMediaIsReadLowercasedAndOnlyFormDataReaderTheBody() {
        // `mime.ParseMediaType` lowercases the media type before it is compared, so a patch that
        // compared the content type as the request wrote it fails on this input.
        let upper = FeverForm(method: "GET", contentType: "Multipart/Form-Data; boundary=x",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n")
        #expect(upper.value(named: "a") == "first", "the media type as the reference reads it")
        #expect(upper.value(named: "api_key") == "Q", "the query half is read whatever the body answers")

        // A multipart media that is not `form-data` is not this read: `multipartReader` reports
        // `ErrNotMultipart`, which `FormValue` discards.
        let mixed = FeverForm(method: "GET", contentType: "multipart/mixed; boundary=x",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n")
        #expect(mixed.value(named: "a") == "", "the wrong media is not read")
        #expect(mixed.value(named: "api_key") == "Q", "and the query half is still read")

        // An empty content type is `mime: no media type` for the same read.
        #expect(FeverForm(method: "GET", contentType: "",
            query: "api_key=Q", body: "--x\r\nname=a\r\n\r\nfirst\r\n--x--\r\n").value(named: "a") == "",
            "a request with no content type is not a multipart request")
    }

    @Test func theBoundaryHasToComeFromTheContentType() {
        let body = "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n"

        // `ErrMissingBoundary`: the read reports an error, so nothing from the body is read. A
        // patch that took the boundary from the body itself would read this input.
        let noBoundary = FeverForm(method: "GET", contentType: "multipart/form-data",
            query: "api_key=Q", body: body)
        #expect(noBoundary.value(named: "a") == "", "no boundary parameter, no body read")
        #expect(noBoundary.value(named: "api_key") == "Q", "the query half is read before the body")

        // The boundary is a parameter, so a quoted one is the same boundary; the pins read the
        // reference's answer for a quoted value against the unquoted one above.
        let quoted = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=\"x\"",
            query: "api_key=Q", body: body)
        #expect(quoted.value(named: "a") == "first", "the parameter as `ParseMediaType` reads it")
    }

    @Test func aMalformedParameterIsTheErrorTheReadReportsWhileTheTypeSurvivesIt() {
        // `consumeMediaParam` answers a trailing semicolon as nothing to read, which is not the
        // error, so this body is read. A patch that treated an empty parameter as the error
        // answered nothing here.
        let trailing = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x;",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n")
        #expect(trailing.value(named: "a") == "first", "a trailing semicolon is not the error")

        // A pair with no `=` is `ErrInvalidMediaParameter`, so the parameters are nothing and there
        // is no boundary to read the body with. A patch that skipped the pair instead
        // answered `first`.
        let noEquals = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x; name",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n")
        #expect(noEquals.value(named: "a") == "", "the parameters are nothing for the error")
        #expect(noEquals.value(named: "api_key") == "Q", "the query half is read whatever the body answers")

        // The media type is answered with the error, which is why `parsePostForm` reads its body
        // for the same shape: `PostForm` is copied before the query pairs, so this request answers
        // the body value. A patch that answered nothing for the error read the query value
        // here instead.
        let urlencoded = FeverForm(method: "POST", contentType: "application/x-www-form-urlencoded; name",
            query: "api_key=Q", body: "api_key=body")
        #expect(urlencoded.value(named: "api_key") == "body", "the type survives the parameter error")

        // The disposition half swallows the error and keeps the type without the parameters, so a
        // part whose disposition carries a malformed parameter has no name and is skipped, while
        // the simple part in the same body is still read. A patch that stored the empty value named
        // this part.
        let malformed = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
            body: "--x\r\nContent-Disposition: form-data; name=a; q=\r\n\r\nvalue\r\n"
                + "--x\r\nContent-Disposition: form-data; name=b\r\n\r\nsimple\r\n--x--\r\n")
        #expect(malformed.values(named: "a") == [], "a part with a malformed disposition has no name")
        #expect(malformed.values(named: "b") == ["simple"], "the part that is a simple part")
    }

    @Test func aPartThatCannotBeReadEndsTheWholeBodyRead() {
        // `ReadForm` builds its own map and hands it back only when the whole read is clean, so the
        // pair read before the failure is not in `r.Form` either. A patch that put each part in the
        // form as it read it would answer `first` here.
        let half = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q",
            body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n"
                + "--x\r\nContent-Disposition: form-data; name=b\r\n\r\nsecond\r\njunk")
        #expect(half.values(named: "a") == [], "the part read before the failure is not read")
        #expect(half.value(named: "api_key") == "Q", "and the form keeps what the query read gave")

        // A body that never reaches its closing boundary is the same failure.
        let noClosing = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q",
            body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n")
        #expect(noClosing.values(named: "a") == [], "no closing boundary, nothing read")

        // A body whose boundary is not the one the content type names is the same failure again.
        let wrongBoundary = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q",
            body: "--y\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--y--\r\n")
        #expect(wrongBoundary.values(named: "a") == [], "the boundary comes from the content type")
    }

    @Test func onlySimplePartsLandInTheForm() {
        let body = "--x\r\nContent-Disposition: form-data; name=file; filename=p.png\r\n\r\nbytes\r\n"
            + "--x\r\nContent-Disposition: attachment; name=notform\r\n\r\nvalue\r\n"
            + "--x\r\nContent-Disposition: form-data\r\n\r\nvalue\r\n"
            + "--x\r\nX-Custom: 1\r\n\r\nvalue\r\n"
            + "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nsimple\r\n--x--\r\n"
        let form = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "", body: body)

        // `form.File` is not `form.Value`, so a part with a filename never reaches `r.Form`;
        // `FormName` answers nothing for a disposition that is not `form-data`; a part with no name
        // is skipped with `continue`; and a part with no `Content-Disposition` has no name to read.
        #expect(form.values(named: "file") == [], "a file part is not a form value")
        #expect(form.values(named: "notform") == [], "the disposition is read as form-data")
        #expect(form.value(named: "") == "", "a part with no name is skipped")
        #expect(form.values(named: "a") == ["simple"], "the part that is a simple part")

        // `FileName` answers the empty string for a filename parameter that is empty, so this part
        // is a value part rather than a file one. A patch that looked at whether the parameter was
        // present at all answered nothing for it.
        let noFilename = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
            body: "--x\r\nContent-Disposition: form-data; name=a; filename=\"\"\r\n\r\nbytes\r\n--x--\r\n")
        #expect(noFilename.values(named: "a") == ["bytes"], "the empty filename is not a file part")
    }

    @Test func aHeaderLineWithoutAColonEndsTheWholeRead() {
        // `readMIMEHeader` reports a ProtocolError for a line with no colon, so `ReadForm` fails
        // and the part read before that line is not in `r.Form` either. A patch that skipped the
        // line and kept reading answered `first` here.
        let form = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q",
            body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n"
                + "--x\r\nContent-Disposition: form-data; name=b\r\nmalformed line\r\n\r\nsecond\r\n--x--\r\n")
        #expect(form.values(named: "a") == [], "the whole read fails on that line")
        #expect(form.value(named: "api_key") == "Q", "and the form keeps what the query read gave")
    }

    @Test func thePartValueIsTheBytesAsWrittenAndLineEndingsAreGoReaderRules() {
        // The urlencoded half decodes `+` and `%`; this half does not, because the value is the
        // part body read as it is. A patch that reused the escaping rule here answered "A b".
        let raw = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\n%41+b\r\n--x--\r\n")
        #expect(raw.value(named: "a") == "%41+b", "the bytes as the read gets them")

        // Go's reader accepts a bare LF as a line ending, so this body is read. A patch that
        // required CRLF before each boundary answered nothing here.
        let lf = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "", body: "--x\nContent-Disposition: form-data; name=a\n\nvalue\n--x--\n")
        #expect(lf.value(named: "a") == "value", "the line ending as Go's reader reads it")
    }

    @Test func theOrderPerNameIsBodyThenQueryThenPartsAndTheMethodDecidesTheBodyHalf() {
        // `ParseForm` copies `PostForm` into `r.Form` before the query pairs, and
        // `ParseMultipartForm` appends its values after both. A patch that appended the parts
        // before the query answered `part` for the first name here.
        let queryFirst = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=api_key\r\n\r\npart\r\n--x--\r\n")
        #expect(queryFirst.value(named: "api_key") == "Q", "the query pair comes before the part")
        #expect(queryFirst.values(named: "api_key") == ["Q", "part"], "the whole order for that name")

        // For the urlencoded half the body comes first, which `GoogleReaderAuthTests` pins for this
        // path's sibling read; the two halves meet on the same name here.
        let bodyFirst = FeverForm(method: "POST", contentType: "application/x-www-form-urlencoded",
            query: "mark=group", body: "mark=item")
        #expect(bodyFirst.value(named: "mark") == "item", "the urlencoded body pair comes first")

        // The body half is read only for the three methods `ParseForm` names, so a GET with an
        // urlencoded body answers the query value, not the body one.
        let notRead = FeverForm(method: "GET", contentType: "application/x-www-form-urlencoded",
            query: "api_key=Q", body: "api_key=body")
        #expect(notRead.value(named: "api_key") == "Q", "GET does not read the urlencoded body half")

        // The multipart half is read whatever the method is, which is what `FormValue` calls
        // `ParseMultipartForm` for: the same body on POST is read, so the method guard belongs to
        // the urlencoded half only.
        let postPart = FeverForm(method: "POST", contentType: "multipart/form-data; boundary=x",
            query: "api_key=Q", body: "--x\r\nContent-Disposition: form-data; name=a\r\n\r\nfirst\r\n--x--\r\n")
        #expect(postPart.value(named: "a") == "first", "the multipart half is read for any method")
    }

    @Test func thePartThatDeclaresQuotedPrintableIsDecoded() {
        let qp = "Content-Transfer-Encoding: quoted-printable"

        // The values the form carries for this part, so the answer for a part the decoder reports an
        // error on is the empty form rather than the empty value, which is what `FormValue` answers
        // for both.
        func read(_ content: String, _ header: String = qp) -> [String] {
            let body = "--x\r\nContent-Disposition: form-data; name=a\r\n" +
                (header.isEmpty ? "" : header + "\r\n") + "\r\n" + content + "\r\n--x--\r\n"
            return FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
                body: body).values(named: "a")
        }

        // The answers below are the reference's own for these inputs, read by a program that ran the
        // same read. A patch that skipped the decoder answered the bytes as written for every one of
        // them.
        #expect(read("=41=20=42") == ["A B"], "the hex pair")
        #expect(read("abc=\r\ndef") == ["abcdef"], "the soft line break on CRLF")
        #expect(read("abc=\ndef") == ["abcdef"], "the soft line break on a bare LF, which is the deviation from RFC 2045")
        #expect(read("abc= \t\r\ndef") == ["abcdef"], "the whitespace between the break and the line ending")

        // The line ending inside the part survives the trim that the break check runs, and the one
        // before the delimiter is not part of the value, which is the rule the pins above read.
        #expect(read("abc\r\ndef") == ["abc\r\ndef"], "the CRLF inside the part")
        #expect(read("abc\ndef") == ["abc\ndef"], "the LF inside the part")

        // A `=` at the end of the part is the break at the end of the read, which the decoder takes,
        // and the whitespace before the line ending is part of the break. A `=` that is the whole line
        // is not: the break has to have something before it to be the break at the end.
        #expect(read("abc=") == ["abc"], "the break at the end of the part")
        #expect(read("=41= ") == ["A"], "the break at the end with the whitespace it takes")
        #expect(read("=") == [], "the break with nothing before it is the error")

        // An `=` that is not a hex pair and not at the end of the line is the literal character, so
        // these are not the error the decoder reports.
        #expect(read("a=x") == ["a=x"], "the literal equals")
        #expect(read("=4a") == ["J"], "lowercase hex is accepted, so this pair decodes")
        #expect(read("a=zz") == ["a=zz"], "the literal equals, which is what this pair falls back to")
        #expect(read("a=z") == ["a=z"], "one character after the equals is the literal too")
        #expect(read("=41= \tq\r\n=42") == ["A= \tq\r\nB"], "the literal equals after the pair, with the line ending it keeps")

        // An empty line inside the part is the line ending it keeps, not a break.
        #expect(read("=41\r\n\r\n=42") == ["A\r\n\r\nB"], "the empty line inside the part")

        // The tab is not a break and survives; a control byte is the error, which ends the whole body
        // read rather than this part alone. A byte at or above 0x80 is the extension that passes
        // through, and 0x7F is not part of it.
        #expect(read("a\tb") == ["a\tb"], "the tab that is not a break")
        #expect(read("a\u{01}b") == [], "the control byte ends the body read")
        #expect(read("a\u{7F}b") == [], "the byte at 0x7F ends the body read")
        #expect(read("a\u{00E9}b") == ["a\u{00E9}b"], "the byte at or above 0x80 passes through")

        // The name is compared without case, and so is its value.
        #expect(read("=41", "content-transfer-encoding: quoted-printable") == ["A"],
            "the name compared without case")
        #expect(read("=41", "Content-Transfer-Encoding: Quoted-Printable") == ["A"],
            "the value compared without case")
        #expect(read("=41", "Content-Transfer-Encoding: quoted-printable ") == ["A"],
            "the whitespace `trim` takes from the end of the header line")

        // The first value with the name wins, so a part that declares another encoding first is not
        // decoded, and a part that declares nothing is not decoded either.
        #expect(read("=41", "Content-Transfer-Encoding: 8bit\r\nContent-Transfer-Encoding: quoted-printable") == ["=41"],
            "the first value with the name")
        #expect(read("=41", "Content-Transfer-Encoding: 8bit") == ["=41"], "another encoding is not decoded")
        #expect(read("=41", "") == ["=41"], "a part that declares nothing is not decoded")
        #expect(read("=41", "Content-Transfer-Encoding:") == ["=41"], "an empty value is not the encoding")

        // The header order does not matter: the encoding is read whatever line it comes on.
        let before = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
            body: "--x\r\nContent-Transfer-Encoding: quoted-printable\r\n"
                + "Content-Disposition: form-data; name=a\r\n\r\n=41\r\n--x--\r\n")
        #expect(before.values(named: "a") == ["A"], "the encoding read before the disposition")

        // A part with no name is skipped before the copy, so it is never decoded and the error it
        // would report does not end the read; a named part is copied whatever kind it is, so a file
        // part reaches the decoder even though this read keeps none of its bytes.
        let skipped = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
            body: "--x\r\nContent-Disposition: form-data; name=a\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=41\r\n"
                + "--x\r\nContent-Disposition: form-data; name=\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\na\u{01}b\r\n--x--\r\n")
        #expect(skipped.values(named: "a") == ["A"], "a part with no name is skipped before the copy")
        let filePart = FeverForm(method: "GET", contentType: "multipart/form-data; boundary=x", query: "",
            body: "--x\r\nContent-Disposition: form-data; name=a\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=41\r\n"
                + "--x\r\nContent-Disposition: form-data; name=b; filename=f\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\na\u{01}b\r\n--x--\r\n")
        #expect(filePart.values(named: "a") == [], "a named file part reaches the decoder")
    }
}
