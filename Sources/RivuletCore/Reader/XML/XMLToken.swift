// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The token kinds
// are those `encoding/xml` reports, and the tree is what its `Decode` builds from them.

import Foundation

/// A token the tokenizer reports.
enum XMLToken: Equatable, Sendable {
    case startElement(XMLName, [XMLAttribute])
    case endElement(XMLName)
    case characterData(String)
    case comment(String)
    case processingInstruction(target: String, content: String)
    case directive(String)
}
