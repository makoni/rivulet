// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The name model
// follows `encoding/xml`'s `Name`.

import Foundation

/// An element or attribute name: the namespace it resolves to and its local part.
///
/// The namespace is the one the tokenizer resolves from the declarations in scope, the way
/// `encoding/xml` translates names: an undefined prefix stays as written, and `xml` resolves to the
/// XML namespace.
struct XMLName: Equatable, Sendable {
    var namespace: String
    var local: String

    /// Whether the name has this local part, and this namespace when one is given. A model field in
    /// the reference matches on the local name alone unless its tag names a namespace, so an empty
    /// `namespace` matches any namespace.
    func matches(local: String, namespace: String = "") -> Bool {
        self.local == local && (namespace.isEmpty || self.namespace == namespace)
    }

    /// Whether the name is the one a model field with this namespace and local part matches, once the
    /// default space is applied: `translate` substitutes `DefaultSpace` for a name with no prefix, and
    /// the tree has already resolved a declared default namespace, so a name that reaches this with an
    /// empty namespace is one that had no prefix at all.
    func matches(local: String, namespace: String, defaultSpace: String) -> Bool {
        local == self.local && (namespace.isEmpty || namespace == resolvedNamespace(defaultSpace: defaultSpace))
    }

    /// The namespace `translate` resolves this name to for an element name, with `defaultSpace`
    /// standing in for a name that had no prefix.
    private func resolvedNamespace(defaultSpace: String) -> String {
        namespace.isEmpty ? defaultSpace : namespace
    }

    /// Whether the text can be an XML name, which is what `encoding/xml`'s `isName` decides.
    ///
    /// A digit cannot start a name, even though `readName` reads digits as name bytes, so `1tag`
    /// reads as a name and then fails this check. Go decides it against two explicit
    /// `unicode.RangeTable`s; Swift does not expose `General_Category`, so the classes here are the
    /// approximation recorded in `docs/parity.md`.
    static func isValidName(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        guard isNameStart(first) else { return false }
        return text.unicodeScalars.dropFirst().allSatisfy { isNameStart($0) || isNamePart($0) }
    }

    /// The ASCII bytes `encoding/xml`'s `isNameByte` accepts, which is what `readName` reads a name
    /// over. Reading a name is not the same as being one: `1tag` reads as a name and then fails the
    /// check above.
    static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ||
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) ||
            (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) ||
            byte == UInt8(ascii: "_") || byte == UInt8(ascii: ":") ||
            byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
    }

    /// The characters `attrval` reads an unquoted attribute value over. It is not the class above:
    /// `encoding/xml` writes out this list in full, without the `.`, so a value stops at a dot even
    /// though a name would not.
    static func isAttributeValueByte(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ||
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) ||
            (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) ||
            byte == UInt8(ascii: "_") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "-")
    }
}

/// The characters a name may start with: Go's `first` table, which is letters plus `:` and `_`.
private func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
    Character(scalar).isLetter || scalar == ":" || scalar == "_"
}

/// The characters a name may continue with: Go's `second` table, which is letters, numbers and
/// marks plus `-`, `.` and the middle dot. Swift exposes marks as the grapheme-extend property.
private func isNamePart(_ scalar: Unicode.Scalar) -> Bool {
    isNameStart(scalar) || Character(scalar).isNumber || scalar.properties.isGraphemeExtend
        || scalar == "-" || scalar == "." || scalar == "·"
}
