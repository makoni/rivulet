// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/atom/atom_common.go (`AtomPerson`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// One Person construct: the name element, and the email element when the name is empty, each
/// trimmed on its own. Both are read at the person's own level, and the field tags name no
/// namespace, so they match any namespace, and a single-value field takes the last element that
/// matches.
struct AtomPerson: Equatable, Sendable {
    var element: XMLElement

    /// The Person constructs at the element's own level, in the namespace the field tag names. The
    /// order is the order the reference collects a slice of them in, which is what the sorted name
    /// list reads.
    static func read(from scope: XMLElement, namespace: String) -> [AtomPerson] {
        scope.children(local: "author", namespace: namespace).map { AtomPerson(element: $0) }
    }

    /// `PersonName()`.
    var personName: String {
        let name = UnicodeSpace.trim(text(local: "name"))
        return name.isEmpty ? UnicodeSpace.trim(text(local: "email")) : name
    }

    private func text(local: String) -> String {
        element.children(local: local, namespace: "").last?.text ?? ""
    }
}
