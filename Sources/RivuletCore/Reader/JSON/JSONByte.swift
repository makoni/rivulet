// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes. `JSONScanner` names the source the rules are traced against.

/// The bytes the machine compares a byte against, named once so the positions and the literals read
/// the same characters as the same names.
enum JSONByte {
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let doubleQuote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")
    static let leftBrace = UInt8(ascii: "{")
    static let rightBrace = UInt8(ascii: "}")
    static let leftBracket = UInt8(ascii: "[")
    static let rightBracket = UInt8(ascii: "]")
    static let dot = UInt8(ascii: ".")
    static let plus = UInt8(ascii: "+")
    static let hyphen = UInt8(ascii: "-")
    static let slash = UInt8(ascii: "/")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseB = UInt8(ascii: "b")
    static let lowercaseE = UInt8(ascii: "e")
    static let lowercaseF = UInt8(ascii: "f")
    static let lowercaseL = UInt8(ascii: "l")
    static let lowercaseN = UInt8(ascii: "n")
    static let lowercaseR = UInt8(ascii: "r")
    static let lowercaseS = UInt8(ascii: "s")
    static let lowercaseT = UInt8(ascii: "t")
    static let lowercaseU = UInt8(ascii: "u")
    static let uppercaseA = UInt8(ascii: "A")
    static let uppercaseE = UInt8(ascii: "E")
    static let uppercaseF = UInt8(ascii: "F")
}
