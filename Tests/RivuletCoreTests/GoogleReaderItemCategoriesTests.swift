import Testing
@testable import RivuletCore

/// The categories list one item document carries, as `streamItemContentsHandler` builds it
/// (`internal/googlereader/handler.go` at `c4d54f87`).
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order the four
/// parts are appended in — the reading-list first, then the label, then the two flags — which a
/// patch that put the label before the reading-list fails on; that the label is written only when
/// the row has a title, that the read part is written only for a read entry, and that the starred
/// part is written only for a starred row, each on an input where the other two parts are present
/// so the order is still visible; and that the prefix carries the user number, which is the
/// difference from the generic prefix the document's own `id` field uses — a patch that used
/// `user/-/` here answered the same for one user only when the number it wrote was the one the pin
/// reads.
///
/// What these pins cannot fail on: which row the four values come from, which is the storage read
/// and not this rule, and which of the two forms the handler writes for a given document field,
/// which is the handler's choice and is pinned by the socket suite.
@Suite struct GoogleReaderItemCategoriesTests {
    @Test func theFourPartsAreAppendedInThatOrder() {
        // All four parts are present, so a patch that swapped any two of them fails here.
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .read, starred: true,
            categoryTitle: "Tech") == [
                "user/7/state/com.google/reading-list",
                "user/7/label/Tech",
                "user/7/state/com.google/read",
                "user/7/state/com.google/starred",
            ], "the order the handler appends them in")

        // The label alone, with the read part absent, is still before the starred part: the order
        // is not the same as the order the flags are read in.
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .unread, starred: true,
            categoryTitle: "Tech") == [
                "user/7/state/com.google/reading-list",
                "user/7/label/Tech",
                "user/7/state/com.google/starred",
            ], "the label is written before the flags even when the read part is not")
    }

    @Test func eachPartIsWrittenOnlyForItsOwnValue() {
        // The reading-list part is written whatever the row is, so the empty list cannot happen
        // here.
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .unread, starred: false,
            categoryTitle: "") == ["user/7/state/com.google/reading-list"],
            "an input that writes only the first part")

        // One part at a time, each with the first part present so the omission is the difference.
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .read, starred: false,
            categoryTitle: "") == ["user/7/state/com.google/reading-list",
            "user/7/state/com.google/read"], "the read part is written for a read row only")
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .unread, starred: true,
            categoryTitle: "") == ["user/7/state/com.google/reading-list",
            "user/7/state/com.google/starred"], "the starred part is written for a starred row only")
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .unread, starred: false,
            categoryTitle: "Tech") == ["user/7/state/com.google/reading-list", "user/7/label/Tech"],
            "the label part is written for a row with a title only")
    }

    @Test func thePrefixCarriesTheUserNumberWhileTheDocumentIdUsesTheGenericPrefix() {
        // The handler builds the categories with the user-specific prefix and writes the document
        // `id` from the literal, so the two forms are two different values for the same rule name.
        #expect(GoogleReaderItemCategories.categories(userID: 7, status: .unread, starred: false,
            categoryTitle: "") == ["user/7/state/com.google/reading-list"],
            "the categories carry the number, not the generic prefix")
    }
}
