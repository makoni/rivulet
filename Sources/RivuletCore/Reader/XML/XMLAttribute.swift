// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. It is the model
// `encoding/xml`'s `Attr`.

import Foundation

/// An attribute of a start tag, with its name translated the way `encoding/xml` translates it: the
/// declarations in scope apply to element names and to other attribute names, but `xmlns` itself is
/// left as written, and an attribute with no prefix is not moved into the default namespace.
struct XMLAttribute: Equatable, Sendable {
    var name: XMLName
    var value: String
}
