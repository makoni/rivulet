// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux `appendSortedSeq` (`internal/reader/rss/adapter.go`), which is the same rule as
// `makeSorted` in `internal/reader/atom/atom_common.go` (Apache-2.0); adapted for Swift/SQLite.

/// The name list the format adapters build for an entry's tags: names are inserted in sorted position,
/// a name already present is not inserted again, and an empty name is not inserted at all.
///
/// The order is the plain comparison Go does on the string, not a case-insensitive one, which is why
/// an uppercase label sorts before a lowercase one.
struct SortedNames: Equatable, Sendable {
    private(set) var names: [String] = []

    /// `appendSortedSeq` with one value: the transform is the caller's, and the zero value it produces
    /// is what this skips before the search.
    mutating func insert(_ name: String) {
        guard !name.isEmpty else { return }

        let position = names.partitioningIndex { $0 >= name }
        if position < names.count, names[position] == name { return }
        names.insert(name, at: position)
    }
}
