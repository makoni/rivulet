import Testing
@testable import RivuletCore

/// The stream rules the Google Reader router reads: `internal/googlereader/stream.go` at
/// `c4d54f87`. The goldens are the reference's own output at the toolchain `go.mod` pins, including
/// the error wording, which is what the 500 answer writes.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the feed branch,
/// which a patch that read the whole value as the id fails on `feed/123`; the two forms of the
/// stream prefix, which are an OR in the reference's `switch`, so a patch that required both fails
/// on `user/-/state/com.google/read` read with user 7; the two forms of the label prefix, which are
/// the same OR, so the same patch fails on `user/-/label/x`; that the prefix is removed before the
/// suffix is compared, which a patch that compared the whole value against the suffix list fails on
/// `user/7/state/com.google/zzz`; the seven suffixes, which a patch that dropped one fails; the
/// empty value, which answers no stream without an error; the fallback error for a value that
/// matches no prefix; and the error for a stream prefix with an unknown suffix, which names the
/// part left after the prefix was removed rather than the whole value.
///
/// What these pins cannot fail on: the order the two prefixes are removed in, because no input this
/// suite can build is affected by it — a value that carries the user form never carries the generic
/// one, and the same is true for the labels; and the name each stream type prints in the
/// reference's log line, which is not part of any answer this port writes.
@Suite struct GoogleReaderStreamTests {
    private let userID = 7

    private func errorDescription(for streamID: String) -> String? {
        do {
            _ = try GoogleReaderStream.parse(streamID: streamID, userID: userID)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test func theFeedBranchKeepsThePartAfterThePrefix() throws {
        let stream = try GoogleReaderStream.parse(streamID: "feed/123", userID: userID)
        #expect(stream.type == .feed, "the feed branch")
        #expect(stream.id == "123", "the id is what is left after the prefix")

        // An empty part is still a part: a patch that skipped empty values answered nothing here.
        #expect(try GoogleReaderStream.parse(streamID: "feed/", userID: userID).id == "", "the empty feed id")

        // The digits after the feed prefix are not read as a number here; that read is the
        // handler's.
        #expect(try GoogleReaderStream.parse(streamID: "feed/00000000148b9369", userID: userID).id ==
            "00000000148b9369", "the value is kept as it is read")
    }

    @Test func theTwoFormsOfTheStreamPrefixAreAnOr() throws {
        // The reference's `switch` case has two conditions, which is an OR, so the generic form is
        // enough on its own; a patch that required both forms reported the fallback error for this
        // input.
        let generic = try GoogleReaderStream.parse(streamID: "user/-/state/com.google/starred", userID: userID)
        #expect(generic.type == .starred, "the generic form matches on its own")
        #expect(try GoogleReaderStream.parse(streamID: "user/7/state/com.google/read", userID: userID).type ==
            .read, "the user form matches on its own")

        // A value with another user's number carries neither form this read answers for user 7, so
        // it falls through to the fallback error, which names the whole value.
        #expect(errorDescription(for: "user/8/state/com.google/read") ==
            "googlereader: unknown stream type: user/8/state/com.google/read", "another user's stream")

        // The suffix is compared with what is left after the prefix, so an empty suffix is not one
        // of the seven, and the error names that empty part.
        #expect(errorDescription(for: "user/-/state/com.google/") ==
            "googlereader: unknown stream with id: ", "the error names the part that is left")
    }

    @Test func theSevenSuffixesAreRead() throws {
        let suffixes: [(String, GoogleReaderStreamType)] = [
            ("read", .read), ("starred", .starred), ("reading-list", .readingList),
            ("kept-unread", .keptUnread), ("broadcast", .broadcast),
            ("broadcast-friends", .broadcastFriends), ("like", .like),
        ]
        for (suffix, type) in suffixes {
            let stream = try GoogleReaderStream.parse(streamID: "user/-/state/com.google/\(suffix)",
                userID: userID)
            #expect(stream.type == type, "the suffix \(suffix)")
            #expect(stream.id == "", "a stream suffix carries no id")
        }

        // A suffix that is not one of the seven answers the error that names what is left, and the
        // wording is the reference's own.
        #expect(errorDescription(for: "user/7/state/com.google/zzz") ==
            "googlereader: unknown stream with id: zzz", "the suffix read last has no case of its own")
    }

    @Test func theLabelBranchKeepsThePartAfterThePrefix() throws {
        let label = try GoogleReaderStream.parse(streamID: "user/-/label/x", userID: userID)
        #expect(label.type == .label, "the label branch")
        #expect(label.id == "x", "the label as it is read")

        // A label that carries a slash is one value, because the prefix is removed before the rest
        // is read: a patch that split the label on the slash answered `tag` here.
        #expect(try GoogleReaderStream.parse(streamID: "user/7/label/tag/xyz", userID: userID).id == "tag/xyz",
            "the part after the prefix, with its slash")

        // The user form on its own, which is the other half of the OR the reference's case is.
        #expect(try GoogleReaderStream.parse(streamID: "user/7/label/x", userID: userID).id == "x",
            "the user form matches on its own")
        #expect(errorDescription(for: "user/8/label/x") ==
            "googlereader: unknown stream type: user/8/label/x", "another user's label")

        // An empty label is still the label branch, not the fallback error.
        #expect(try GoogleReaderStream.parse(streamID: "user/-/label/", userID: userID).id == "",
            "the empty label")
    }

    @Test func theEmptyValueIsNoStreamWithoutAnErrorAndAnythingElseIsAnError() throws {
        let empty = try GoogleReaderStream.parse(streamID: "", userID: userID)
        #expect(empty.type == .noStream, "the empty value is no stream")
        #expect(errorDescription(for: "") == nil, "and the reference reports no error for it")

        #expect(errorDescription(for: "bogus") == "googlereader: unknown stream type: bogus",
            "the fallback error is the reference's wording")
    }
}
