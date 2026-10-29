// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The piece is what
// `encoding/xml` reports between an element's tags.

import Foundation

/// One piece of an element's content, kept in the order the tokens come.
///
/// The order is what the tree has to keep, because the reference reads an element's content two ways
/// and they do not agree: a value read as `",chardata"` keeps only the character data at the
/// element's own level, while `innerContent` writes every character token it reads, including the
/// ones inside a child element.
enum XMLContentPiece: Equatable, Sendable {
    indirect case text(text: String, isCDATA: Bool)
    indirect case element(XMLElement)

    /// The piece as the reference writes it into the content it keeps: ordinary text is written as it
    /// was read, a run that came from a CDATA section keeps its marker, and a child is written as its
    /// own markup.
    var rendered: String {
        switch self {
        case .text(let value, false): return value
        case .text(let value, true): return "<![CDATA[" + value + "]]>"
        case .element(let child): return child.renderedTag
        }
    }

    var text: String? {
        if case .text(let value, _) = self { return value }
        return nil
    }

    var element: XMLElement? {
        if case .element(let value) = self { return value }
        return nil
    }
}
