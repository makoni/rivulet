// Ported from Go's `mime.ParseMediaType` and `mime/multipart.Reader`, which
// `Request.ParseMultipartForm` reads through (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore

/// The multipart half of the form read.
///
/// Go builds its own map from the body and puts it into `r.Form` only when the whole read is clean,
/// so a part that cannot be read takes the parts read before it with it: this read answers nothing
/// rather than the parts it managed to read. Only value parts land in `r.Form`; a part whose
/// filename parameter is not empty goes to `form.File`, and a part whose disposition is not
/// `form-data`, or that has no name, is skipped. The value is the part body as the bytes are
/// written: Go decodes a part that carries `Content-Transfer-Encoding: quoted-printable`, which
/// this port does not, and that difference is in the stage-7 backlog.
enum FeverMultipartRead {
    /// A value part as `r.Form` holds it.
    struct Value {
        let name: String
        let value: String
    }

    /// The media type and its parameters. `parameters` is nothing for the parameters this read
    /// reports an error for — a pair with no `=`, or one whose value is empty as written — and the
    /// type is still answered with that error, which is why `parsePostForm` reads its body for a
    /// content type whose parameters are malformed while the multipart half does not read the body.
    /// The disposition half swallows the error and keeps the type without the parameters, which is
    /// what leaves a part with a malformed disposition with no name. Only an empty media type is
    /// nothing at all, and `FormValue` discards both errors.
    struct Media {
        let type: String
        let parameters: [String: String]?
    }

    /// `mime.ParseMediaType`: the type is the token before the first `;` with its leading spaces
    /// and tabs taken off, and it is lowercased before it is compared. The parameters are the pairs
    /// after that `;`, with the names lowercased and the quotes taken off a quoted value. What the
    /// pins cannot show: a `;` inside a quoted value, which the reference reads as part of the
    /// value, and a lone quote, which is the value that drops the parameters.
    static func mediaType(_ value: String) -> Media? {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        let head = leadingLWS(parts.first ?? "")
        guard !head.isEmpty else { return nil }

        var parameters: [String: String]? = [:]
        for raw in parts.dropFirst() {
            // An empty parameter is nothing to read, which is what a trailing semicolon gives and
            // which `consumeMediaParam` does not report as an error. A pair with no `=`, or a value
            // that is empty as written, is `ErrInvalidMediaParameter`.
            let parameter = leadingLWS(raw)
            if parameter.isEmpty { continue }
            guard let equals = parameter.firstIndex(of: "=") else { return Media(
                type: String(head).lowercased(), parameters: nil) }
            let text = String(parameter[parameter.index(after: equals)...])
            let quoted = text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2
            let parameterValue = quoted ? String(text.dropFirst().dropLast()) : text
            guard quoted || !parameterValue.isEmpty else { return Media(
                type: String(head).lowercased(), parameters: nil) }
            parameters?[String(parameter[..<equals]).lowercased()] = parameterValue
        }
        return Media(type: String(head).lowercased(), parameters: parameters)
    }

    /// The value parts, in the order the body carries them, or nothing for a body this read cannot
    /// finish. The bytes are the part content as it is written: the escaping rule of the urlencoded
    /// half does not reach here, and a line ending can be a bare `LF` — which Go's reader
    /// switches to when the first delimiter line ends with one.
    static func parts(contentType: String, body: String) -> [Value]? {
        guard let media = mediaType(contentType), media.type == "multipart/form-data",
            let boundary = media.parameters?["boundary"] else { return nil }

        var rest = body[...]
        var ending = "\r\n"
        let marker = "--" + boundary
        let finalMarker = marker + "--"
        var partsRead = 0

        func line() -> Substring? {
            guard !rest.isEmpty else { return nil }
            // The newline is read as a scalar, not as a grapheme: `\r\n` is one `Character` in
            // Swift, so the grapheme view cannot find the newline on its own.
            guard let found = rest.range(of: "\n") else {
                // A run that ends without a line ending is what the reader reports as a failure, so
                // the line is returned as it is and nothing is left to read.
                let whole = rest
                rest = Substring("")
                return whole
            }
            let whole = rest[rest.startIndex..<found.upperBound]
            rest = rest[found.upperBound...]
            return whole
        }

        // `isFinalBoundary`, which is `^--boundary--[ \t]*(\r\n)?$`.
        func isFinalBoundary(_ candidate: Substring) -> Bool {
            guard candidate.hasPrefix(finalMarker) else { return false }
            let tail = leadingLWS(candidate.dropFirst(finalMarker.count))
            return tail.isEmpty || tail == ending
        }

        // `isBoundaryDelimiterLine`, which is `^--boundary--[ \t]*` followed by the line ending. On
        // the first part the reader switches to a bare LF, which is the rule the pins read.
        func isDelimiterLine(_ candidate: Substring) -> Bool {
            guard candidate.hasPrefix(marker) else { return false }
            // `skipLWSPChar` removes leading spaces and tabs only, so the line ending is
            // still read.
            let tail = leadingLWS(candidate.dropFirst(marker.count))
            if partsRead == 0 && tail == "\n" { ending = "\n" }
            return tail == ending
        }

        // `skipPreamble`: the reader scans until the first delimiter line.
        var found = false
        while let read = line() {
            if isDelimiterLine(read) { partsRead += 1; found = true; break }
        }
        guard found else { return nil }

        var values: [Value] = []
        while true {
            // The part headers, up to the empty line that ends them. `Header.Get` takes the first
            // value with a name, so this name keeps the first line it reads.
            var disposition = ""
            while let read = line() {
                if read == ending { break }
                // `readMIMEHeader` reports a ProtocolError for a line with no colon, and
                // `ReadForm` returns it, so the whole body read fails rather than this line
                // being skipped.
                guard let colon = read.firstIndex(of: ":") else { return nil }
                guard String(read[read.startIndex..<colon]).lowercased() == "content-disposition" else {
                    continue
                }
                let value = String(leadingLWS(read[read.index(after: colon)...]))
                if disposition.isEmpty { disposition = String(value.dropLast(ending.count)) }
            }

            // The part content, up to the delimiter match. Go's scan returns the bytes before the
            // match, so the line ending that comes before it is not part of the value, and a body
            // that runs into the delimiter without one is the failure this read reports.
            var data = ""
            var closed = false
            var final = false
            while let read = line() {
                if isFinalBoundary(read) { final = true; closed = true; break }
                if isDelimiterLine(read) { closed = true; break }
                data += String(read)
            }
            guard closed, data.isEmpty || data.hasSuffix(ending) else { return nil }
            partsRead += 1

            // `FormName` and `FileName`, both read from the same disposition: only `form-data`
            // gives a name, and a part with no name is skipped with `continue`. `FileName` answers
            // the empty string for a filename parameter that is empty, so only a non-empty one
            // makes this a file part.
            let parsed = mediaType(disposition)
            guard parsed?.type == "form-data" else { continue }
            let parameters = parsed?.parameters ?? [:]
            let name = parameters["name"] ?? ""
            if name.isEmpty || !(parameters["filename"] ?? "").isEmpty { continue }
            // A body that begins with the delimiter itself is the empty value, which is Go's `total
            // == 0` branch of the scan rather than a failure.
            values.append(Value(name: name, value: data.isEmpty ? "" : String(data.dropLast(ending.count))))
            if final { break }
        }
        return values
    }

    /// `skipLWSPChar`: leading spaces and tabs, which is not the whole whitespace set — the line
    /// ending has to survive, because the delimiter rule reads it.
    private static func leadingLWS(_ value: Substring) -> Substring {
        value.drop { $0 == " " || $0 == "\t" }
    }
}
