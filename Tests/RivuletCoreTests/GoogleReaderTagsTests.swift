import Testing
@testable import RivuletCore

/// The tag rules `edit-tag` reads: `checkAndSimplifyTags` (`internal/googlereader/handler.go` at
/// `c4d54f87`). The goldens are the reference's own output for these inputs at the toolchain
/// `go.mod` pins, including the error wording, which is what the 500 answer writes.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the value each
/// branch writes — `read` is true for the add loop and false for the remove loop, and the same type
/// answers the other value for `kept-unread`, which a patch that read one value per type fails; the
/// order the two loops run in, which a patch that ran the remove loop first fails on `add read`
/// with `remove kept-unread`, where the add loop's write is what the remove loop's guard sees; the
/// same pair also fails on a patch that made that guard compare the value's own type, which is why
/// the guard is named here; `add kept-unread` with `remove read` answers the error under both
/// orders, so it cannot pin the order; that the add loop keeps the last value it reads rather than
/// the first, which a patch that stopped at the first value fails on `add kept-unread` with
/// `add read`; the two wordings, which name different things — the pair of suffixes for the read
/// guard and the single suffix for the starred guard, so a patch that used one wording for both
/// fails; that `broadcast` and `like` write nothing and are not the unsupported error, which a
/// patch that read them as a branch that writes fails; and the unsupported branch, which names the
/// type as the reference prints it — the pins read two types, so a patch that wrote one wording for
/// every type fails on the other one.
///
/// What these pins cannot fail on: the add loop's `read` guard, which asks whether the map holds
/// `KeptUnreadStream` and can never be true because that loop writes only `ReadStream` and
/// `StarredStream` — the pins read what that guard leaves behind, which is the last value written
/// for the order the other guard allows; and the guard that an empty add and an empty remove answer
/// the reference's own wording, which is the handler's rule and not this function's, so it lands
/// with the handler.
@Suite struct GoogleReaderTagsTests {
    private let state = "user/-/state/com.google/"

    /// The streams as the reference's read builds them. A value that is not one of the seven
    /// suffixes is the input the unsupported branch answers for.
    private func tags(_ ids: String...) throws -> [GoogleReaderStream] {
        try streams(ids)
    }

    private func streams(_ ids: [String]) throws -> [GoogleReaderStream] {
        try ids.map { try GoogleReaderStream.parse(streamID: $0, userID: 7) }
    }

    private func errorDescription(adds: [String], removes: [String]) throws -> String? {
        do {
            _ = try GoogleReaderTags.simplify(adds: streams(adds), removes: streams(removes))
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test func eachBranchWritesTheValueThatBranchAnswersFor() throws {
        // The add loop writes true for `read` and false for `kept-unread`, which is the same type
        // answering the other way. A patch that wrote one value per type failed one of these two.
        #expect(try GoogleReaderTags.simplify(adds: tags(state + "read"), removes: []) == [.read: true],
            "add read")
        #expect(try GoogleReaderTags.simplify(adds: tags(state + "kept-unread"), removes: []) ==
            [.read: false], "add kept-unread is the same type read the other way")
        #expect(try GoogleReaderTags.simplify(adds: tags(state + "starred"), removes: []) == [.starred: true],
            "add starred")

        // The remove loop writes the other value for the same type, which is what a patch that
        // reused the add loop's values fails on.
        #expect(try GoogleReaderTags.simplify(adds: [], removes: tags(state + "read")) == [.read: false],
            "remove read")
        #expect(try GoogleReaderTags.simplify(adds: [], removes: tags(state + "kept-unread")) == [.read: true],
            "remove kept-unread is the same type read the other way")
        #expect(try GoogleReaderTags.simplify(adds: [], removes: tags(state + "starred")) == [.starred: false],
            "remove starred")
    }

    @Test func theAddLoopRunsBeforeTheRemoveLoop() throws {
        // The add loop writes first, so this pair is the error for the guard. A patch that ran the
        // remove loop first answered nothing, because that guard saw an empty map; the same pair
        // answered nothing when the guard compared the value's own type.
        #expect(try errorDescription(adds: [state + "read"], removes: [state + "kept-unread"]) ==
            "googlereader: kept-unread and read should not be supplied simultaneously",
            "the add loop wrote read before the remove loop read the guard")

        // The guard answers nothing when only one loop has a value, which is what a patch that
        // reported it for any single value fails on.
        #expect(try errorDescription(adds: [state + "read"], removes: []) == nil, "one loop alone is no conflict")
    }

    @Test func theAddLoopKeepsTheLastValueItReadsForTheOrderItsGuardAllows() throws {
        // The add loop's `read` guard asks for a key that loop never writes, so for this order both
        // values are read and the last one is what the map holds. A patch that stopped at the first
        // value answered false here.
        #expect(try GoogleReaderTags.simplify(
            adds: tags(state + "kept-unread", state + "read"), removes: []) == [.read: true],
            "the last value the add loop read")

        // The other guard in the same loop asks for the key the loop does write, so the reverse
        // order is the error. A patch that made the first guard live by comparing the value's own
        // type instead of the map answered no error for this input.
        #expect(try errorDescription(adds: [state + "read", state + "kept-unread"], removes: []) ==
            "googlereader: kept-unread and read should not be supplied simultaneously",
            "the guard that reads the map, not the value")

        // The same value twice is still that value, which is what a patch that reported the guard
        // for a repeated value fails on.
        #expect(try GoogleReaderTags.simplify(
            adds: tags(state + "starred", state + "starred"), removes: []) == [.starred: true],
            "and the same value twice is still that value")
    }

    @Test func theTwoWordingsNameDifferentThings() throws {
        // The read guard names the two suffixes in the order the reference builds the error from:
        // kept-unread first, read second.
        #expect(try errorDescription(adds: [state + "read"], removes: [state + "read"]) ==
            "googlereader: kept-unread and read should not be supplied simultaneously",
            "the pair of suffixes")

        // The starred guard names one suffix, and it is a different sentence. A patch that used the
        // first wording for both failed here.
        #expect(try errorDescription(adds: [state + "starred"], removes: [state + "starred"]) ==
            "googlereader: starred should not be supplied for add and remove simultaneously",
            "the single suffix of the starred guard")
    }

    @Test func broadcastAndLikeWriteNothingAndAreNotAnError() throws {
        // These two branches log and continue, so the map answers nothing for them and the request
        // is not the unsupported error either. A patch that wrote a value, or that fell through to
        // the unsupported branch, failed both halves of each loop.
        #expect(try GoogleReaderTags.simplify(adds: tags(state + "broadcast"), removes: []) == [:],
            "broadcast writes nothing")
        #expect(try GoogleReaderTags.simplify(adds: tags(state + "like"), removes: []) == [:],
            "like writes nothing")
        #expect(try GoogleReaderTags.simplify(adds: [], removes: tags(state + "broadcast")) == [:],
            "and the remove loop reads broadcast the same way")
        #expect(try GoogleReaderTags.simplify(adds: [], removes: tags(state + "like")) == [:],
            "and the remove loop reads like the same way")
    }

    @Test func theUnsupportedBranchNamesTheTypeAsTheReferencePrintsIt() throws {
        // Only the seven suffixes are tag types, so a label and a feed are the inputs that reach
        // this branch, and the wording names the type rather than the label or the id. A patch that
        // wrote one wording for every type failed the second of these two.
        #expect(try errorDescription(adds: ["user/-/label/x"], removes: []) ==
            "googlereader: unsupported tag type: LabelStream",
            "the type as the reference prints it, not the label name")
        #expect(try errorDescription(adds: ["feed/1"], removes: []) ==
            "googlereader: unsupported tag type: FeedStream", "the other type the same branch names")

        // The control, which is what a patch that reported the error for any value fails on: a tag
        // type and no value at all both answer nothing here.
        #expect(try errorDescription(adds: [state + "read"], removes: []) == nil, "a tag type is not the error")
        #expect(try errorDescription(adds: [], removes: []) == nil, "no tag is nothing to write")
    }
}
