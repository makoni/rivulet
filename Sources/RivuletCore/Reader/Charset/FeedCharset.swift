// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/encoding/encoding.go (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// Errors raised while converting feed bytes to UTF-8.
public enum CharsetError: Error, Equatable, Sendable {
    /// The document declares a label that is not one of the WHATWG labels, and the bytes are
    /// not valid UTF-8, so the label has to be honored and cannot be resolved.
    case unsupportedLabel(String)
}

/// Charset conversion for feed and HTML documents.
///
/// Ported from Miniflux `internal/reader/encoding/encoding.go` and the encoding-related
/// helpers of `internal/reader/xml/decoder.go`. Both entry points share the same rule: a
/// document that is already valid UTF-8 is never converted, whatever label it declares.
public enum FeedCharset {
    /// Converts a document declared with `label` to UTF-8.
    ///
    /// Port of the reference `CharsetReader`: when the document is already valid UTF-8 it is
    /// returned unchanged and the label is not consulted at all — a wrong label in the XML
    /// prolog therefore cannot double-encode a valid document. Otherwise the label is resolved
    /// through the WHATWG label table and the document is decoded with it, replacing bytes the
    /// encoding leaves undefined with U+FFFD.
    ///
    /// - Throws: ``CharsetError/unsupportedLabel(_:)`` when the label cannot be resolved, which
    ///   includes a label the platform has no converter for.
    public static func decode(_ data: Data, label: String) throws -> Data {
        if isValidUTF8(data) { return data }
        guard let encoding = CharsetEncoding.named(label), let strategy = encoding.decoderStrategy else {
            throw CharsetError.unsupportedLabel(label)
        }
        return CharsetDecoder.decode(data, using: strategy, canonicalName: encoding.rawValue)
    }

    /// Converts an HTML document to UTF-8 using its content type and contents.
    ///
    /// Port of the reference `NewCharsetReaderFromBytes`: valid UTF-8 passes through unchanged;
    /// otherwise the encoding is determined from a byte-order mark, the `charset` parameter of
    /// `contentType`, a `<meta>` prescan of the first 1024 bytes, the "looks like UTF-8"
    /// heuristic, or the `windows-1252` default, and the whole document is decoded with the
    /// result. A label that is not a WHATWG label is not an error on this path: the reference
    /// falls through to the next detection step, which the tests pin. The "looks like UTF-8"
    /// heuristic and a `utf-16` declaration leave the bytes as they are, because the reference
    /// uses `encoding.Nop` there.
    ///
    /// The only case where the platform cannot do what the reference does is an encoding its
    /// converter registry does not know; the test that every canonical encoding resolves pins
    /// that this does not happen today, and such a document is returned unchanged.
    public static func decode(_ data: Data, contentType: String?) -> Data {
        if isValidUTF8(data) { return data }
        let preview = Data(data.prefix(1024))
        guard let encoding = CharsetDetection.detectedEncoding(preview: preview, contentType: contentType),
              let strategy = encoding.decoderStrategy else {
            return data
        }
        return CharsetDecoder.decode(data, using: strategy, canonicalName: encoding.rawValue)
    }

    /// Drops bytes and characters an XML 1.0 parser must reject.
    ///
    /// Port of the reference `xml.filterValidXMLChars`: invalid UTF-8 sequences and characters
    /// outside the XML `Char` production are removed; the replacement character U+FFFD itself is
    /// removed as well, exactly like the reference, which drops every rune it decodes as
    /// `utf8.RuneError`.
    public static func filterInvalidXMLCharacters(_ data: Data) -> Data {
        var scalars = String.UnicodeScalarView()
        for scalar in String(decoding: data, as: UTF8.self).unicodeScalars {
            if scalar == "\u{FFFD}" { continue }
            guard isXMLCharacter(scalar) else { continue }
            scalars.append(scalar)
        }
        return Data(String(scalars).utf8)
    }

    /// Reports whether the document's XML declaration says `utf-8` or has no declaration.
    ///
    /// Port of the reference `xml.hasUTF8XMLDeclaration`. Like the reference, the scan looks for
    /// `encoding=` in the whole document rather than only in the prolog, so text in the body can
    /// decide the answer for a document without a declaration. The comparison is ASCII-only, as
    /// the reference's `bytes.EqualFold` is.
    public static func declaresUTF8XMLDeclaration(_ data: Data) -> Bool {
        guard let declared = CharsetDetection.declaredEncoding(in: data) else { return true }
        return isASCIIEqualFold(declared, "utf-8")
    }

    /// ASCII case-insensitive comparison, the reference's `bytes.EqualFold`.
    private static func isASCIIEqualFold(_ left: String, _ right: String) -> Bool {
        func fold(_ text: String) -> [UInt8] {
            text.utf8.map { byte in
                (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ? byte + 0x20 : byte
            }
        }
        return fold(left) == fold(right)
    }

    /// XML 1.0 `Char`: tab, newline, carriage return, and the legal ranges.
    /// Characters of XML's `Char` production, the same rule `filterInvalidXMLCharacters`
    /// removes with, and which `text` still reports for a numeric character reference: a value like
    /// `&#0;` resolves to a character outside the production, and the reference fails there.
    static func isXMLCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
            return true
        default:
            return false
        }
    }

    /// Strict UTF-8 validation, the reference's `utf8.Valid`.
    private static func isValidUTF8(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8) != nil
    }
}
