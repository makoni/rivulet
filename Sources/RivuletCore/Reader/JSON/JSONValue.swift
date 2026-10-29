// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the shape is what the reference's decoder produces for the
// value it reads. `JSONScanner` names the source the rules are traced against.

/// A JSON value as the reader keeps it.
///
/// The number is kept as the literal text as the machine read it, because `encoding/json` keeps the
/// literal and converts it per target type: `d.value` records the bytes, and `UseNumber` aside, the
/// conversion is a property of the target, not of the value. So the shape here keeps the literal,
/// and the rules that read a number into a target — `ParseInt` failures, an `int64` field, `null`
/// into a string field — belong to the adapter, which pins them.
enum JSONValue: Equatable, Sendable {
    /// The members in the order the document wrote them.
    ///
    /// The reference folds an object into `map[string]any`, which keeps no order and keeps one
    /// value per key; the tree keeps what the document wrote, because the field read walks it and
    /// takes the last effective assignment, which is what the reference's map ends up holding.
    case object(members: [JSONMember])

    /// The elements in the order the document wrote them. An empty container is a value, not an
    /// error, because `arrayInterface` and `objectInterface` return an empty non-nil collection.
    case array(values: [JSONValue])

    /// A string as the machine decoded it: the escapes written out, the bytes made well-formed.
    case string(String)

    /// A number as the machine read it, not as a value converted to a target type.
    case number(text: String)

    case boolean(Bool)

    /// `null`, which `d.value` reports as a value. What it does to a field is the field read's
    /// rule.
    case null
}
