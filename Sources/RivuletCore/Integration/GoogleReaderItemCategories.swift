// Ported from Miniflux internal/googlereader/handler.go's category list for one item (Apache-2.0);
// adapted for Swift/SQLite.

/// The categories one item document carries.
///
/// The order is the order the handler appends the parts in, which `GoogleReaderItemCategoriesTests`
/// pins: the reading-list first, then the label, then the two flags. The label is written only for
/// a row with a title, the read part only for a read row, the starred part only for a starred row,
/// and the first part is written whatever the row is, so the list is never empty.
///
/// The prefix here carries the user number. The document's own `id` field uses the generic form, so
/// the same rule name has two forms; the handler chooses which one it writes.
public enum GoogleReaderItemCategories {
    private static let readingListSuffix = "reading-list"
    private static let readSuffix = "read"
    private static let starredSuffix = "starred"

    /// The list for one row, in the order the handler appends it.
    ///
    /// - Parameters:
    ///   - userID: The user the prefix is built with.
    ///   - status: The row status the read part is written for.
    ///   - starred: The flag the starred part is written for.
    ///   - categoryTitle: The category title the label part is written for.
    public static func categories(userID: Int, status: EntryStatus, starred: Bool,
        categoryTitle: String) -> [String] {
        let userStreamPrefix = "user/\(userID)/state/com.google/"
        var categories: [String] = [userStreamPrefix + readingListSuffix]
        if !categoryTitle.isEmpty {
            categories.append("user/\(userID)/label/" + categoryTitle)
        }
        if status == .read {
            categories.append(userStreamPrefix + readSuffix)
        }
        if starred {
            categories.append(userStreamPrefix + starredSuffix)
        }
        return categories
    }
}
