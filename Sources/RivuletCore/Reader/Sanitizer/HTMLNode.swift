// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// A node of the tree the fragment builder builds, the shape `Node` holds.
///
/// The reference keeps the comment nodes it reads, and the renderer answers with nothing for them,
/// so the builder does not record them at all; what the sanitizer sees is the same output. The
/// parent pointer is not kept either, because the only rule that reads it is foster parenting,
/// which is outside the subset recorded in `docs/parity.md`.
final class HTMLNode {
    enum Kind: Equatable {
        case document
        case element
        case text
    }

    let kind: Kind
    /// The lower-cased element name, or `""` for the other kinds.
    var name: String = ""
    var text: String = ""
    var attributes: [HTMLAttribute] = []
    var children: [HTMLNode] = []

    init(kind: Kind, name: String = "") {
        self.kind = kind
        self.name = name
    }

    var firstChild: HTMLNode? { children.first }

    func appendChild(_ child: HTMLNode) {
        children.append(child)
    }
}
