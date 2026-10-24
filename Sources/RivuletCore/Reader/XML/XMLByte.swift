// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The bytes the reader compares markup against, named once so the scanner and the tokenizer read
/// the same characters as the same names.
enum XMLByte {
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let ampersand = UInt8(ascii: "&")
    static let semicolon = UInt8(ascii: ";")
    static let hash = UInt8(ascii: "#")
    static let slash = UInt8(ascii: "/")
    static let questionMark = UInt8(ascii: "?")
    static let exclamation = UInt8(ascii: "!")
    static let hyphen = UInt8(ascii: "-")
    static let equals = UInt8(ascii: "=")
    static let doubleQuote = UInt8(ascii: "\"")
    static let singleQuote = UInt8(ascii: "'")
    static let leftBracket = UInt8(ascii: "[")
    static let rightBracket = UInt8(ascii: "]")
    static let lowercaseX = UInt8(ascii: "x")
}
