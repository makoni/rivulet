// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser/format.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// What format detection answers: the format, and the Atom version when the format is Atom.
///
/// The reference returns an empty version for every other format, which is `nil` here. For Atom it
/// is `1.0`, or `0.3` when the root element says so.
struct DetectedFormat: Equatable, Sendable {
    var format: FeedFormat
    var version: String? = nil
}
