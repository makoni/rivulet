// Ported from Miniflux internal/model/category.go (Apache-2.0); adapted for Swift/SQLite.

/// The two counts the reference's category carries as pointers with `omitempty`.
///
/// The reference reads them only through `CategoriesWithFeedCount`, so a category read the plain way
/// has nothing for them. The pointer is what makes the two answers differ: the half that read them
/// writes them even for a zero, and the half that did not writes nothing. This port carries the fact
/// as a separate value rather than as fields on the row, because the row has no columns for them.
public struct CategoryCounts: Equatable, Sendable {
    /// The number of feed rows of this account under the category.
    public let feedCount: Int

    /// The number of entries of this account with the status the read counts, under the category.
    public let totalUnread: Int

    /// Counts answered for one category.
    public init(feedCount: Int, totalUnread: Int) {
        self.feedCount = feedCount
        self.totalUnread = totalUnread
    }
}

/// A category with the counts the half that reads them answered for it.
public struct CategoryWithCounts: Sendable {
    /// The row the read answered.
    public let category: Category

    /// The counts the half that reads them answered for it.
    public let counts: CategoryCounts

    /// A category with the counts read for it.
    public init(category: Category, counts: CategoryCounts) {
        self.category = category
        self.counts = counts
    }
}
