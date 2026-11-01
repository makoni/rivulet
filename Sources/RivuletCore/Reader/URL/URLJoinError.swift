// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/urllib (`JoinBaseURLAndPath`, the two guards before the join)
// (Apache-2.0); adapted for Swift/SQLite.

/// Why a base URL and a path element cannot be joined. The reference reports these as messages, so
/// this port keeps them typed and a pin compares the branch rather than the wording.
enum URLJoinError: Error, Equatable, Sendable {
    /// The reference's guard for an empty base URL.
    case emptyBaseURL

    /// The reference's guard for an empty path.
    case emptyPath

    /// A base the URL layer's parse cannot read, which is the case Go reports from `url.Parse`.
    case invalidBase(URLParseError)
}
