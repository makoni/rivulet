// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// An element of the tree the reader builds.
///
/// `text` is the character data directly inside the element, in document order, with entities
/// decoded — what the reference reads when a model field is a string. Whitespace is kept as the
/// reference keeps it at this level and is trimmed by the format adapters, which is where the
/// reference trims it.
struct XMLElement: Equatable, Sendable {
    var name: XMLName
    var attributes: [XMLAttribute]
    var children: [XMLElement]
    var text: String

    /// The first direct child with this local name, and namespace when one is given.
    func child(local: String, namespace: String = "") -> XMLElement? {
        children.first { $0.name.matches(local: local, namespace: namespace) }
    }

    /// Every direct child with this local name, and namespace when one is given.
    func children(local: String, namespace: String = "") -> [XMLElement] {
        children.filter { $0.name.matches(local: local, namespace: namespace) }
    }

    /// The value of a direct attribute with this local name, and namespace when one is given. An
    /// attribute with no prefix is not in the default namespace, so an empty `namespace` matches it.
    func attribute(local: String, namespace: String = "") -> String? {
        attributes.first { $0.name.matches(local: local, namespace: namespace) }?.value
    }
}
