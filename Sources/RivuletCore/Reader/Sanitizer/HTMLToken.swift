// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// One token the HTML tokenizer produces: text, a start tag, an end tag, a self-closing start tag
/// or a comment. `golang.org/x/net/html` also has a doctype token, which the reader answers with
/// the comment case, as `readMarkupDeclaration` does.
struct HTMLToken {
    enum Kind: Equatable {
        case text
        case startTag
        case endTag
        case selfClosingStartTag
        case comment
    }

    /// The lower-cased tag name for a tag token, or `""` for a text or comment token.
    var kind: Kind
    var name: String
    var data: String
    var attributes: [HTMLAttribute]

    init(kind: Kind, name: String = "", data: String = "", attributes: [HTMLAttribute] = []) {
        self.kind = kind
        self.name = name
        self.data = data
        self.attributes = attributes
    }
}
