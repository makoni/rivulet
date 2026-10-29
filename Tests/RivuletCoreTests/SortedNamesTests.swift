import Testing
@testable import RivuletCore

/// The tag list the adapters build. Ported from Miniflux `appendSortedSeq`
/// (`internal/reader/rss/adapter.go`, and the same rule as `makeSorted` in
/// `internal/reader/atom/atom_common.go`): a name is inserted in sorted position, a name already
/// present is not inserted again, and an empty name is not inserted at all.
@Suite struct SortedNamesTests {
    /// The corpus case that pins the order: the input order does not decide the output, because the
    /// list is kept sorted as it is built.
    ///
    /// `TestParseEntryWithCategories`
    @Test func insertionKeepsTheListSorted() {
        var names = SortedNames()
        for name in ["Category 1", "Category 2", "Category 0"] { names.insert(name) }
        #expect(names.names == ["Category 0", "Category 1", "Category 2"])
    }

    /// `TestParseEntryWithCategories` — `slices.BinarySearch` finds the name already there, so the
    /// duplicate is not inserted again.
    @Test func aNameAlreadyPresentIsNotInsertedAgain() {
        var names = SortedNames()
        for name in ["Category 1", "Category 2", "Category 2"] { names.insert(name) }
        #expect(names.names == ["Category 1", "Category 2"])
    }

    /// `TestParseEntryWithCategories` — the value the transform produced is empty, which is Go's
    /// zero value, so the element is skipped.
    @Test func anEmptyNameIsNotInserted() {
        var names = SortedNames()
        names.insert("")
        names.insert("Category 1")
        names.insert("")
        #expect(names.names == ["Category 1"])
    }

    /// Traced: the insert happens at the position `BinarySearch` reported, so a name can land in
    /// the middle of the list rather than at the end.
    @Test func aNameIsInsertedWhereTheSearchSays() {
        var names = SortedNames()
        for name in ["b", "d", "a", "c"] { names.insert(name) }
        #expect(names.names == ["a", "b", "c", "d"])
    }

    /// The order is the plain comparison Go does on the string, not a case-insensitive one, so an
    /// uppercase label sorts before a lowercase one.
    @Test func theOrderIsThePlainStringComparison() {
        var names = SortedNames()
        for name in ["Visual Art", "ace"] { names.insert(name) }
        #expect(names.names == ["Visual Art", "ace"])
    }
}
