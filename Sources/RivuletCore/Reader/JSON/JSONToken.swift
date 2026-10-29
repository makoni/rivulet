// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the tokens are the positions `encoding/json`'s scanner
// reports. `JSONScanner` names the source the rules are traced against.

/// A token the token machine reports.
///
/// The kinds are the opcodes the reference's scanner returns, which are what the tree is built
/// from: the two separators are `scanObjectKey` and `scanObjectValue`/`scanArrayValue`, and a key
/// is the literal read at a key position, decoded by the same rules as a string value.
enum JSONToken: Equatable, Sendable {
    case objectStart
    case objectEnd
    case arrayStart
    case arrayEnd

    /// A key, decoded through the same rules a string value is decoded by.
    case key(String)

    /// The `:` after a key.
    case valueSeparator

    /// The `,` between members or between elements.
    case memberSeparator

    /// A value read at a value position.
    case value(JSONValue)
}
