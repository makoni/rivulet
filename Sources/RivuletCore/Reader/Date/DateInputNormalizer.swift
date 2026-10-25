// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/date/parser.go
// (`replacer`); adapted for Swift/SQLite.

import Foundation

/// The normalization the reference applies to a date before it tries any layout: zone locations
/// written as names, localized day and month names, and the two weekday spellings that are not Go's
/// own.
///
/// The scan is over UTF-8 bytes, as Go's is. Every pattern begins with an ASCII byte, so a match
/// can never begin inside a multi-byte character, and Go takes the pair with the highest priority,
/// which is the first one in table order matching at a position. The only pair whose pattern is a
/// prefix of another is `Mai`, and the longer `Mai ` is listed first, with the same trailing space
/// in its replacement, so the result is the same under either rule. The groups below are the
/// comments the reference puts on its own table.
enum DateInputNormalizer {
    private static let replacements: [(old: String, new: String)] = [
        // Timezones
        ("Europe/Brussels", "CET"),
        ("America/Los_Angeles", "PDT"),
        ("GMT+0000 (Coordinated Universal Time)", "GMT"),
        ("GMT-", "GMT -"),

        // Localized dates
        ("Mo,", "Mon,"),
        ("Di,", "Tue,"),
        ("Mi,", "Wed,"),
        ("Do,", "Thu,"),
        ("Fr,", "Fri,"),
        ("Sa,", "Sat,"),
        ("So,", "Sun,"),
        ("Mär ", "Mar "),
        ("Mai ", "May "),
        ("Okt ", "Oct "),
        ("Dez ", "Dec "),
        ("lun,", "Mon,"),
        ("mar,", "Tue,"),
        ("mer,", "Wed,"),
        ("jeu,", "Thu,"),
        ("ven,", "Fri,"),
        ("sam,", "Sat,"),
        ("dim,", "Sun,"),
        ("lun.", "Mon"),
        ("mar.", "Tue"),
        ("mer.", "Wed"),
        ("jeu.", "Thu"),
        ("ven.", "Fri"),
        ("sam.", "Sat"),
        ("dim.", "Sun"),
        ("Lundi,", "Monday,"),
        ("Mardi,", "Tuesday,"),
        ("Mercredi,", "Wednesday,"),
        ("Jeudi,", "Thursday,"),
        ("Vendredi,", "Friday,"),
        ("Samedi,", "Saturday,"),
        ("Dimanche,", "Sunday,"),
        ("jan.", "January "),
        ("feb.", "February "),
        ("mars.", "March "),
        ("avril.", "April "),
        ("mai.", "May "),
        ("juin.", "June "),
        ("juil.", "July"),
        ("août.", "August"),
        ("sept.", "September"),
        ("oct.", "October"),
        ("nov.", "November"),
        ("dec.", "December"),
        ("déc.", "December"),
        ("janvier ", "January "),
        ("février ", "February "),
        ("mars ", "March "),
        ("avril ", "April "),
        ("mai ", "May "),
        ("juin ", "June "),
        ("juillet ", "July"),
        ("août ", "August"),
        ("septembre ", "September"),
        ("octobre ", "October"),
        ("november ", "November"),
        ("décembre ", "December"),
        ("Janvier", "January"),
        ("Février", "February"),
        ("Mars", "March"),
        ("Avril", "April"),
        ("Mai", "May"),
        ("Juin", "June"),
        ("Juillet", "July"),
        ("Août", "August"),
        ("Septembre", "September"),
        ("Octobre", "October"),
        ("Novembre", "November"),
        ("Décembre", "December"),
        ("avr ", "Apr "),
        ("mai ", "May "),
        ("jui ", "Jun "),
        ("juin ", "June "),
        ("Thurs,", "Thu,"),
        ("Thur,", "Thu,"),
    ]

    /// The same table as bytes, prepared once, because that is what Go scans and what decides which
    /// pattern wins at a position.
    private static let byteTable: [(pattern: [UInt8], replacement: [UInt8])] =
        replacements.map { (Array($0.old.utf8), Array($0.new.utf8)) }

    /// The normalized form of the input, as the reference builds it before the layout loop.
    static func normalized(_ input: String) -> String {
        let bytes = Array(input.utf8)
        var output: [UInt8] = []
        var position = 0
        while position < bytes.count {
            if let match = firstMatch(at: position, in: bytes) {
                output.append(contentsOf: match.replacement)
                // The scan advances by the pattern, not by the replacement, which is what Go does.
                position += match.patternLength
                continue
            }
            output.append(bytes[position])
            position += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// The first pair in table order matching at `position`, or `nil` when nothing matches there.
    /// Go's replacer gives each pair a priority by its position in the table, so this is the pair
    /// Go takes. A longest-match reading would pick the same pair for this table: the only pattern
    /// that is a prefix of another is `Mai`, and the longer `Mai ` is listed before it.
    private static func firstMatch(at position: Int, in bytes: [UInt8])
        -> (replacement: [UInt8], patternLength: Int)? {
        for (pattern, replacement) in byteTable {
            guard position + pattern.count <= bytes.count,
                Array(bytes[position..<position + pattern.count]) == pattern else {
                continue
            }
            return (replacement, pattern.count)
        }
        return nil
    }
}
