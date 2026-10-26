// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (`escape.go`) (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// The escaping the sanitizer writes text and attribute values through, which is
/// `html.EscapeString`.
///
/// It is not the escaping the reference's renderer uses for a whole document: the five characters
/// the function knows about are the five the sanitizer can put into its own output.
enum HTMLEscape {
    private static let replacements: [Character: String] = [
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&#34;",
        "'": "&#39;",
    ]

    static func escapeString(_ value: String) -> String {
        guard value.contains(where: { replacements[$0] != nil }) else { return value }

        var out = ""
        for char in value {
            if let replacement = replacements[char] {
                out += replacement
            } else {
                out.append(char)
            }
        }
        return out
    }
}
