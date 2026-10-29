// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the tree is what `Decoder.Decode` builds from the tokens the
// machine reports. `JSONScanner` names the source the rules are traced against.

import Foundation

/// Reads a document into the tree the adapters read fields out of.
///
/// The tree is the first top-level value, which is what `Decode` decodes: the machine stops at the
/// end of it, so the bytes after it are not read. `checkValid`, which `Unmarshal` uses, reads them;
/// the difference is recorded in `docs/parity.md`.
enum JSONReader {
    /// Reads the document and returns its top-level value.
    ///
    /// - Throws: ``JSONError`` for bytes the machine cannot read.
    static func read(_ data: Data) throws -> JSONValue {
        var scanner = JSONScanner(data)
        var tokens: [JSONToken] = []
        while let token = try scanner.nextToken() { tokens.append(token) }

        // `Decode` on a document with no value fails at the end of input, which is what the machine
        // reports, so assembly is only ever asked for a token the machine read.
        guard !tokens.isEmpty else { throw JSONError.unexpectedEnd }
        var index = 0
        return try value(tokens, &index)
    }

    // MARK: - Assembly, one production per `decode.go` function

    /// `d.value`: the token that starts a value. A stream the machine read always starts with one
    /// of the three value-shaped tokens, because the key and the two separators are read by the
    /// loops below and the two closing tokens end them, which is why the reference panics here with
    /// `phasePanicMsg`.
    private static func value(_ tokens: [JSONToken], _ index: inout Int) throws -> JSONValue {
        switch tokens[index] {
        case let .value(value):
            index += 1
            return value
        case .arrayStart:
            index += 1
            return .array(values: try elements(tokens, &index))
        case .objectStart:
            index += 1
            return .object(members: try members(tokens, &index))
        case .key, .valueSeparator, .memberSeparator, .arrayEnd, .objectEnd:
            throw JSONError.unexpectedEnd
        }
    }

    /// `d.array` and `d.arrayInterface`: the elements in the order the document wrote them, in a
    /// collection that is empty rather than nil for an empty container.
    private static func elements(_ tokens: [JSONToken], _ index: inout Int) throws -> [JSONValue] {
        var elements: [JSONValue] = []

        while index < tokens.count {
            switch tokens[index] {
            case .arrayEnd:
                index += 1
                return elements
            case .memberSeparator:
                index += 1
            default:
                elements.append(try value(tokens, &index))
            }
        }

        return elements
    }

    /// `d.object` and `d.objectInterface`: the members in the order the document wrote them, with a
    /// key that appears twice kept as the two members the document wrote rather than folded to one,
    /// which is where the last-wins rule the field read applies comes from. The reference reads the
    /// key, then the colon, then the value, so the separator is consumed here and the value token
    /// is the one after it.
    private static func members(_ tokens: [JSONToken], _ index: inout Int) throws -> [JSONMember] {
        var members: [JSONMember] = []

        while index < tokens.count {
            switch tokens[index] {
            case .objectEnd:
                index += 1
                return members
            case let .key(name):
                index += 1
                while index < tokens.count, tokens[index] == .valueSeparator { index += 1 }
                members.append(JSONMember(key: name, value: try value(tokens, &index)))
            case .valueSeparator, .memberSeparator:
                index += 1
            default:
                index += 1
            }
        }

        return members
    }
}
