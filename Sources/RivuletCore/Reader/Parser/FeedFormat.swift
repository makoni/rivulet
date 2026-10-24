// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser/format.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The feed formats the reference distinguishes.
enum FeedFormat: String, Sendable {
    case rdf
    case rss
    case atom
    case json
    case unknown
}
