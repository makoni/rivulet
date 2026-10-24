// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The failures are
// the ones `encoding/xml` reports with the configuration the reference builds (`Strict = false`).

import Foundation

/// Failures of the tolerant XML reader.
///
/// With `Strict = false` most of what a strict XML reader rejects is tolerated instead, so only the
/// failures the reference can still reach are modeled here; each one is pinned by a test.
enum XMLError: Error, Equatable, Sendable {
    /// The document ended while an element was still open, or had no document at all. The reference
    /// distinguishes a bare `io.EOF` from `unexpected EOF` only in its message.
    case unexpectedEOF

    /// A name that cannot be an XML name, such as one starting with a digit.
    case invalidXMLName(String)

    /// An end tag with no element open for it.
    case unexpectedEndElement(String)

    /// An end tag that cannot be read, such as `</name` followed by something other than `>`.
    case invalidEndTag(String)

    /// A name position that has no name in it: after `<` or `</`.
    case elementNameExpected

    /// An attribute position with no name in it.
    case attributeNameExpected

    /// A `<?` instruction with no target after it.
    case processingInstructionTargetExpected

    /// A `<?xml ?>` instruction declaring a version other than 1.0.
    case unsupportedXMLVersion(String)

    /// `--` inside a comment, or `<!-` that is not the opening of one.
    case malformedComment

    /// `<![` that is not followed by `CDATA[`.
    case malformedCDATA

    /// `]]>` in ordinary text, which only a CDATA section may contain.
    case unescapedBracketInText

    /// `<` inside a quoted attribute value.
    case unescapedAngleInAttributeValue

    /// `/>` that is not closed by `>`.
    case selfClosingTagNotClosed

    /// An end tag whose namespace differs from the namespace of the element it closes, which the
    /// reference still rejects in non-strict mode.
    case endTagNamespaceMismatch(element: XMLName, endTag: XMLName)

    /// A character outside XML's `Char` production, which the reference can still reach through a
    /// numeric character reference: the document is filtered before decoding, but `&#0;` resolves
    /// to a character the production does not allow.
    case illegalCharacterCode(UInt32)

    /// A document read through its declared label when the bytes are not valid UTF-8 and the label
    /// cannot be resolved. The reference wraps `CharsetReader`'s error as `opening charset`.
    case charset(CharsetError)
}
