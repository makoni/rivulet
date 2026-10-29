// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/language/language.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The language tag as a feed declares it, cleaned up for use as an HTML `lang` attribute.
enum Language {
    /// The bound accepted tags have, which `maxLength` sets at 50.
    private static let maxLength = 50

    /// `Normalize`: the value is trimmed, lower-cased, and underscores become hyphens.
    ///
    /// No BCP-47 validation is performed, because many real feeds use loose values and dropping them
    /// silently yields worse behaviour than passing them through. The value is feed-controlled, so
    /// anything outside the tag alphabet `[a-z0-9-]`, or longer than the bound, is rejected rather
    /// than stripped: stripping bad characters could assemble a wrong tag.
    ///
    /// The lower-casing is ASCII-only and happens in the same pass as the charset check, so a
    /// character Unicode case folding would map to ASCII (U+212A to `k`, U+0130 to `i`) cannot turn
    /// input the filter should reject into a tag that looks valid.
    static func normalize(_ value: String) -> String {
        let trimmed = UnicodeSpace.trim(value)
        guard trimmed.utf8.count <= maxLength else { return "" }

        var bytes = [UInt8](trimmed.utf8)
        for index in bytes.indices {
            switch bytes[index] {
            case UInt8(ascii: "A") ... UInt8(ascii: "Z"): bytes[index] += UInt8(ascii: "a") - UInt8(ascii: "A")
            case UInt8(ascii: "_"): bytes[index] = UInt8(ascii: "-")
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "0") ... UInt8(ascii: "9"),
                UInt8(ascii: "-"):
                break
            default: return ""
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
