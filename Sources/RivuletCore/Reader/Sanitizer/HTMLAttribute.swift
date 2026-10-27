// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// One attribute of a start tag, as the tokenizer reads it: the name is lower-cased and the value
/// is decoded, which is what `TagAttr` returns.
struct HTMLAttribute {
    var name: String
    var value: String
}
