// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes. Miniflux has no code to port at this layer: the reference
// reads a JSON feed through `encoding/json`, so this mirrors the part of that source the reader
// reads through — `scanner.go`, `decode.go` and `stream.go` (Go 1.26, the version `go.mod` pins).

import Foundation

/// The token machine the reader assembles the tree from.
///
/// The position decides which byte the machine accepts, and the position is what names the context
/// of a failure, in the words `scanner.go` uses. One top-level value is read, which is where
/// `readValue` breaks at the first `scanEnd`: for a container the byte that closes it is the
/// machine's last token, because `readValue` tests `scanEnd` against an invented space rather than
/// against the byte after it, while for a scalar the byte that ends the literal has to be read,
/// because it is what decides whether the literal had ended. `stateEndTop` reports `scanEnd`
/// whatever that byte is, so the machine stops there without a failure, and the failure it records
/// is what `checkValid`, the path `Unmarshal` takes, reports; `docs/parity.md` records that as a
/// difference.
struct JSONScanner {
    /// The states `pushParseState` puts, which is what `stateEndValue` switches on.
    private enum ParseState {
        case objectKey, objectValue, arrayValue
    }

    /// The position the machine is in, one per `stateX` production.
    private enum Position {
        case beginValue, beginValueOrEmpty, beginKey, beginKeyOrEmpty, endValue, endTop
    }

    /// The number states: `stateNeg`, `state1`, `state0`, `stateDot` and the rest. `state1` falls
    /// through to `state0` and `stateE` falls straight through to `stateESign`, so the byte a state
    /// cannot accept is read by the state it falls through to.
    private enum NumberState {
        case afterHyphen, afterZero, afterNonZero, afterDot, afterDotDigit, afterExponentSign,
            afterExponentDigit
    }

    /// `maxNestingDepth`, the depth `pushParseState` limits to.
    private static let maxNestingDepth = 10_000

    /// `stateT`, `stateF` and `stateN`: the word, the letters it still expects, and the value it
    /// reads as.
    private static let words: [UInt8: (name: String, letters: [UInt8], value: JSONValue)] = [
        JSONByte.lowercaseT: ("true", [JSONByte.lowercaseR, JSONByte.lowercaseU, JSONByte.lowercaseE],
            .boolean(true)),
        JSONByte.lowercaseF: ("false", [JSONByte.lowercaseA, JSONByte.lowercaseL, JSONByte.lowercaseS,
            JSONByte.lowercaseE], .boolean(false)),
        JSONByte.lowercaseN: ("null", [JSONByte.lowercaseU, JSONByte.lowercaseL, JSONByte.lowercaseL], .null),
    ]

    private let bytes: [UInt8]
    private var cursor = 0
    private var parseStates: [ParseState] = []
    private var position: Position = .beginValue
    private var finished = false

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    /// Reads the next token, or `nil` where `readValue` breaks: at the end of the first top-level
    /// value.
    ///
    /// - Throws: ``JSONError`` for a byte the position cannot accept, or for input that ends while
    /// a value is still open.
    mutating func nextToken() throws -> JSONToken? {
        // `readValue` breaks at the first `scanEnd`: for a container that is the invented space it
        // tests, so the byte that closed the container is the machine's last token, and for a
        // scalar it is the byte that ends the literal, because that byte is what decides whether
        // the literal had ended.
        if finished { return nil }

        // `stateEndTop` does not skip space, because the byte that ends a top-level scalar is what
        // decides whether the literal had ended.
        if position != .endTop { skipSeparators() }

        guard let byte = peek() else {
            // At the top level the value is complete, which is where `readValue` breaks; anywhere
            // else the value is still open, which is the failure `readValue` returns.
            if position == .endTop { return nil }
            throw JSONError.unexpectedEnd
        }

        switch position {
        case .endTop:
            // `stateEndTop` reports `scanEnd` whatever the byte is, so `readValue` breaks at it and
            // the machine reports no failure. The failure that state records is what `checkValid`
            // reports; `docs/parity.md` records that as a difference.
            cursor += 1
            finished = true
            return nil
        case .beginKeyOrEmpty where byte == JSONByte.rightBrace:
            cursor += 1
            return pop(returning: .objectEnd)
        case .beginValueOrEmpty where byte == JSONByte.rightBracket:
            cursor += 1
            return pop(returning: .arrayEnd)
        case .beginKey, .beginKeyOrEmpty:
            return try beginKey(byte)
        case .beginValue, .beginValueOrEmpty:
            return try beginValue(byte)
        case .endValue:
            cursor += 1
            return try endValue(byte)
        }
    }

    // MARK: - Positions

    /// `stateBeginString`: a key position requires a string, which is why the failure names the
    /// key.
    private mutating func beginKey(_ byte: UInt8) throws -> JSONToken {
        guard byte == JSONByte.doubleQuote else {
            throw JSONError.unexpectedCharacter(character: byte,
                context: "looking for beginning of object key string")
        }
        cursor += 1
        position = .endValue
        return .key(JSONUnquote.unquote(try readStringLiteral()))
    }

    /// `stateBeginValue`: the byte that can start a value, and the failure for a byte that cannot.
    private mutating func beginValue(_ byte: UInt8) throws -> JSONToken {
        cursor += 1

        switch byte {
        case JSONByte.leftBrace:
            try push(.objectKey)
            position = .beginKeyOrEmpty
            return .objectStart
        case JSONByte.leftBracket:
            try push(.arrayValue)
            position = .beginValueOrEmpty
            return .arrayStart
        case JSONByte.doubleQuote:
            return emitted(.string(JSONUnquote.unquote(try readStringLiteral())))
        case JSONByte.hyphen, JSONByte.zero...JSONByte.nine:
            return emitted(.number(text: try readNumberLiteral(from: byte)))
        case JSONByte.lowercaseT, JSONByte.lowercaseF, JSONByte.lowercaseN:
            return emitted(try readWordLiteral(from: byte))
        default:
            throw JSONError.unexpectedCharacter(character: byte, context: "looking for beginning of value")
        }
    }

    /// `stateEndValue`: the parse state decides the byte that continues the machine, and it names
    /// the failure for a byte that does not.
    private mutating func endValue(_ byte: UInt8) throws -> JSONToken {
        switch parseStates[parseStates.count - 1] {
        case .objectKey:
            guard byte == JSONByte.colon else {
                throw JSONError.unexpectedCharacter(character: byte, context: "after object key")
            }
            parseStates[parseStates.count - 1] = .objectValue
            position = .beginValue
            return .valueSeparator
        case .objectValue:
            if byte == JSONByte.comma {
                parseStates[parseStates.count - 1] = .objectKey
                position = .beginKey
                return .memberSeparator
            }
            if byte == JSONByte.rightBrace { return pop(returning: .objectEnd) }
            throw JSONError.unexpectedCharacter(character: byte, context: "after object key:value pair")
        case .arrayValue:
            if byte == JSONByte.comma {
                position = .beginValue
                return .memberSeparator
            }
            if byte == JSONByte.rightBracket { return pop(returning: .arrayEnd) }
            throw JSONError.unexpectedCharacter(character: byte, context: "after array element")
        }
    }

    /// `pushParseState`, which is the position that limits the depth.
    private mutating func push(_ parseState: ParseState) throws {
        parseStates.append(parseState)
        guard parseStates.count <= JSONScanner.maxNestingDepth else { throw JSONError.maxDepthExceeded }
    }

    /// `popParseState`. At the top level `readValue` breaks at the invented space it tests rather
    /// than at the byte after, so the byte that closed the container is the machine's last token.
    private mutating func pop(returning token: JSONToken) -> JSONToken {
        parseStates.removeLast()
        if parseStates.isEmpty {
            finished = true
        } else {
            position = .endValue
        }
        return token
    }

    /// The token for a value the machine has read, and the position its terminator is read from.
    private mutating func emitted(_ value: JSONValue) -> JSONToken {
        // `stateEndValue` with an empty stack is `stateEndTop`, so the byte that ends a top-level
        // scalar is the next byte the machine reads, and it has to be one of the four separators.
        position = parseStates.isEmpty ? .endTop : .endValue
        return .value(value)
    }

    // MARK: - Literals

    /// `stateInString`: the literal as the bytes wrote it, validated here and written out by
    /// `JSONUnquote`.
    private mutating func readStringLiteral() throws -> [UInt8] {
        var literal: [UInt8] = []

        while let byte = peek() {
            cursor += 1
            switch byte {
            case JSONByte.doubleQuote:
                return literal
            case JSONByte.backslash:
                literal.append(byte)
                guard let escaped = peek() else { throw JSONError.unexpectedEnd }
                cursor += 1
                if escaped == JSONByte.lowercaseU {
                    literal.append(escaped)
                    literal.append(contentsOf: try readHexDigits())
                } else if JSONUnquote.acceptsEscape(escaped) {
                    literal.append(escaped)
                } else {
                    throw JSONError.unexpectedCharacter(character: escaped, context: "in string escape code")
                }
            case let control where control < 0x20:
                throw JSONError.unexpectedCharacter(character: control, context: "in string literal")
            default:
                literal.append(byte)
            }
        }

        // A string that ends early is the failure `readValue` returns, and the reference reports it
        // as the invented space in this state's context only on the `checkValid` path.
        throw JSONError.unexpectedEnd
    }

    /// `stateInStringEscU` and its four digits: the escape that ends early fails at the end of
    /// input.
    private mutating func readHexDigits() throws -> [UInt8] {
        var digits: [UInt8] = []

        for _ in 0 ..< 4 {
            guard let byte = peek() else { throw JSONError.unexpectedEnd }
            guard JSONUnquote.hexDigit(byte) != nil else {
                throw JSONError.unexpectedCharacter(character: byte,
                    context: "in \\u hexadecimal character escape")
            }
            cursor += 1
            digits.append(byte)
        }

        return digits
    }

    /// `stateNeg`, `state1`, `state0` and the rest of the number states. The literal is kept as the
    /// bytes read it, which is what `Number` keeps; converting it is the field read's rule, not the
    /// machine's.
    private mutating func readNumberLiteral(from first: UInt8) throws -> String {
        var literal: [UInt8] = [first]
        var state = numberState(for: first)

        while let byte = peek() {
            guard let next = try numberState(state, byte) else { return text(literal) }
            cursor += 1
            literal.append(byte)
            state = next
        }

        if endsLiteralNumber(state) { return text(literal) }
        throw JSONError.unexpectedEnd
    }

    /// The number state the byte moves to, or `nil` where the production falls through to
    /// `stateEndValue`, which is what ends the literal.
    private func numberState(_ state: NumberState, _ byte: UInt8) throws -> NumberState? {
        switch state {
        case .afterHyphen: // `stateNeg`
            if isDigit(byte) { return numberState(for: byte) }
            throw JSONError.unexpectedCharacter(character: byte, context: "in numeric literal")
        case .afterZero: // `state0`
            if byte == JSONByte.dot { return .afterDot }
            if byte == JSONByte.lowercaseE || byte == JSONByte.uppercaseE { return .afterExponentSign }
            return nil
        case .afterNonZero: // `state1` falls through to `state0`
            if isDigit(byte) { return .afterNonZero }
            return try numberState(.afterZero, byte)
        case .afterDot: // `stateDot`
            if isDigit(byte) { return .afterDotDigit }
            throw JSONError.unexpectedCharacter(character: byte,
                context: "after decimal point in numeric literal")
        case .afterDotDigit: // `stateDot0`
            if isDigit(byte) { return .afterDotDigit }
            if byte == JSONByte.lowercaseE || byte == JSONByte.uppercaseE { return .afterExponentSign }
            return nil
        case .afterExponentSign: // `stateE` falls through to `stateESign`
            if byte == JSONByte.plus || byte == JSONByte.hyphen { return .afterExponentSign }
            if isDigit(byte) { return .afterExponentDigit }
            throw JSONError.unexpectedCharacter(character: byte, context: "in exponent of numeric literal")
        case .afterExponentDigit: // `stateE0`
            if isDigit(byte) { return .afterExponentDigit }
            return nil
        }
    }

    /// `stateT`, `stateF` and `stateN`: the word is walked letter by letter, so a word that ends
    /// early is rejected at the byte that breaks it.
    private mutating func readWordLiteral(from first: UInt8) throws -> JSONValue {
        let word = JSONScanner.words[first]!

        for letter in word.letters {
            guard let byte = peek() else { throw JSONError.unexpectedEnd }
            guard byte == letter else {
                throw JSONError.unexpectedCharacter(character: byte,
                    context: "in literal \(word.name) (expecting '\(letterCharacter(letter))')")
            }
            cursor += 1
        }

        return word.value
    }

    // MARK: - Bytes

    /// `isSpace`: the four bytes, not merely a byte below the printable range.
    private func isSpace(_ byte: UInt8) -> Bool {
        byte <= JSONByte.space && (byte == JSONByte.space || byte == JSONByte.tab
            || byte == JSONByte.carriageReturn || byte == JSONByte.lineFeed)
    }

    private mutating func skipSeparators() {
        while let byte = peek(), isSpace(byte) { cursor += 1 }
    }

    private func peek() -> UInt8? {
        cursor < bytes.count ? bytes[cursor] : nil
    }

    private func numberState(for byte: UInt8) -> NumberState {
        if byte == JSONByte.hyphen { return .afterHyphen }
        return byte == JSONByte.zero ? .afterZero : .afterNonZero
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        JSONByte.zero <= byte && byte <= JSONByte.nine
    }

    // MARK: - End of input

    /// A number state that ends the literal when it sees the space `readValue` tests at the end of
    /// input. `checkValid` names the state for a byte it has already read; for a state that accepts
    /// the space it reports one message, so the state's context is not kept here.
    private func endsLiteralNumber(_ state: NumberState) -> Bool {
        switch state {
        case .afterHyphen, .afterDot, .afterExponentSign: return false
        case .afterZero, .afterNonZero, .afterDotDigit, .afterExponentDigit: return true
        }
    }

    private func letterCharacter(_ byte: UInt8) -> Character {
        Character(Unicode.Scalar(UInt32(byte))!)
    }

    private func text(_ literal: [UInt8]) -> String {
        String(decoding: literal, as: UTF8.self)
    }
}
