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
/// checked by patching the rule and reverting (8 pins, 17 probes): the media type is read as
/// `mime.ParseMediaType` reads it and compared lowercased — 2 probes, one that compared the content
/// type as it was written fails on `Multipart/Form-Data`, one that accepted any multipart media
/// fails on `multipart/mixed`; the parameter rules — 4 probes, for a pair with no `=`, for a value
/// that is empty as written, for a trailing semicolon that is not the error, and for the media type
/// surviving that error on the urlencoded half; the boundary has to be a parameter of the content
/// type — 1 probe, a patch that fell back to its own boundary fails on it; a part that cannot be
/// read ends the whole body read, so the parts read before the failure are not read either — 1
/// probe; the three guards of the part loop — 4 probes, disposition, name, and the filename
/// parameter being empty rather than present; a header line with no colon ends the read — 1 probe;
/// the part value is the bytes as written, which a patch that applied the percent-decoding rule
/// fails on, and a line ending can be a bare `LF`, which a patch that required `CRLF` fails on — 2
/// probes; and the order per name is the urlencoded body pairs, then the query pairs, then the
/// parts, with the method deciding whether an urlencoded body is read at all — 2 probes.
///
/// What these pins cannot show: Go's 10 MB memory threshold and its 1000-part cap, which no input
/// here reaches; the `filename` value as `filepath.Base` cuts it, which only the file half uses and
/// this read never reads; the error values `FormValue` discards, which nothing can be asserted
/// about a read that reports none; and the order of the names, which Go reads through a map and
/// does not fix, so every pin here reads one name at a time. The urlencoded body half itself is
/// pinned by `GoogleReaderAuthTests`; the pair rules shared with the query read are pinned by
/// `GoogleReaderQueryTests`, and this read answers them the same way, as `r.Form` ends up
/// holding them.
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
}
