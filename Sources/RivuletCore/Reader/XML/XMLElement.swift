// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// An element of the tree the reader builds.
///
/// The content is kept as the tokens came, in document order, which is what the reference's two ways
/// of reading an element need: `text` is the character data at the element's own level, the value a
/// model field tagged `",chardata"` gets, and `innerContent` is every character token inside the
/// element, which is what `innerContent` collects. `innerMarkup` is the content as the reference's
/// `",innerxml"` keeps it.
struct XMLElement: Equatable, Sendable {
    var name: XMLName
    var attributes: [XMLAttribute]
    var content: [XMLContentPiece]

    /// The character data at this element's own level, in document order, with character references
    /// decoded — what the reference reads when a model field is a string. Whitespace is kept as the
    /// reference keeps it at this level, and the format adapters trim it, which is where the reference
    /// trims it.
    var text: String { content.compactMap { $0.text }.joined() }

    /// Every character data inside the element, in document order, which is what `innerContent`
    /// collects: `",chardata"` keeps only the level it is read at, this keeps the whole content.
    var innerContent: String { runsInDocumentOrder.compactMap { $0.text }.joined() }

    /// The content as the reference keeps it for `",innerxml"`, which is the markup as well as the
    /// text. A run that came from a CDATA section keeps its marker, because that is what the CDATA
    /// rule reads.
    ///
    /// The reference keeps the bytes it read, so this is a reconstruction: the tree has character data
    /// already decoded, names already translated, and comments, directives and instructions dropped
    /// from the content. Each of the three is recorded in `docs/parity.md`.
    var innerMarkup: String { content.map { $0.rendered }.joined() }

    /// The element written out with its tags, which is what a child contributes to the content the
    /// reference keeps.
    var renderedTag: String {
        "<" + name.local + renderedAttributes + ">" + innerMarkup + "</" + name.local + ">"
    }

    /// The attributes as written, with the names as the tree resolved them.
    private var renderedAttributes: String {
        attributes.map { " " + $0.name.local + "=\"" + $0.value + "\"" }.joined()
    }

    /// The first direct child with this local name, and namespace when one is given.
    func child(local: String, namespace: String = "", defaultSpace: String = "") -> XMLElement? {
        children.first { $0.name.matches(local: local, namespace: namespace, defaultSpace: defaultSpace) }
    }

    /// Every direct child with this local name, and namespace when one is given.
    func children(local: String, namespace: String = "", defaultSpace: String = "") -> [XMLElement] {
        contentElements.filter { $0.name.matches(local: local, namespace: namespace, defaultSpace: defaultSpace) }
    }

    /// An attribute of this element, by local name and namespace. Attribute names are matched as
    /// written, because `translate` does not apply the default space to them.
    func attribute(local: String, namespace: String = "") -> String? {
        attributes.first { $0.name.matches(local: local, namespace: namespace) }?.value
    }

    var children: [XMLElement] { contentElements }

    private var contentElements: [XMLElement] { content.compactMap { $0.element } }

    /// Every character data piece inside this element and its children, in document order.
    private var runsInDocumentOrder: [XMLContentPiece] {
        content.flatMap { piece in
            switch piece {
            case .text: return [piece]
            case .element(let child): return child.runsInDocumentOrder
            }
        }
    }
}
