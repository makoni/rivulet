// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`mandatoryAttributesStruct`) (Apache-2.0);
// adapted for Swift/SQLite.

import Foundation

/// The attributes some tags cannot be written without, the three the sanitizer tracks while it
/// reads the element's attributes.
struct MandatoryAttributes {
    var href = false
    var src = false
    var srcset = false

    mutating func track(_ name: String) {
        switch name {
        case "href": href = true
        case "src": src = true
        case "srcset": srcset = true
        default: break
        }
    }

    /// `hasRequiredAttributes`: the three tags that need one, and every other tag as complete.
    func isComplete(for tag: String) -> Bool {
        switch tag {
        case "a": return href
        case "iframe": return src
        case "source", "img": return src || srcset
        default: return true
        }
    }
}
