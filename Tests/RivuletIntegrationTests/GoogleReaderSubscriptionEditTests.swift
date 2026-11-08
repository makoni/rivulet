import Testing
import RivuletApp
@testable import RivuletCore

/// `editSubscriptionHandler` of `internal/googlereader/handler.go` at `c4d54f87`, over a real
/// socket. The goldens are the reference's own answer for these inputs at the toolchain `go.mod`
/// pins. The stream branches the handler reads are pinned by `GoogleReaderStreamTests`, the form
/// read by `GoogleReaderAuthTests`, the integer read by the write-handler suite, and the storage
/// writes by `FeedManagementReadsTests`.
///
/// What these pins can fail on, each checked by patching the rule and reverting (9 pins, 19
/// probes): that `s` is read as the whole merged list while `a` is the single value the same read
/// answers; that the stream guard is the count of the list, which the same guard answers for a
/// value the read cannot parse; the order that runs that guard before the tag read; the presence
/// test, which answers differently for a name the form carries with an empty value and a name it
/// does not carry; the order that runs the rename before the type check; the title guard, which
/// writes nothing for the empty value; the action switch, including the wording the default case
/// writes for a name the form does not carry; that `unsubscribe` runs the delete for every value of
/// the list; the status the integer read failure maps to here and the answer the delete that finds
/// nothing gives; that `subscribe` answers the read ordered by title when the form carries no tag,
/// creates the category the tag names when it does, and reads that category after creating it; the
/// rule the input fails on; and the status every failure of that branch maps to.
///
/// What these pins cannot show: `rename`'s own empty-title guard, which the handler's title test
/// answers before the read, so no input reaches it; `move`'s category answer, which the type check
/// runs before the read that could answer it, so the read can only answer it for a label the
/// handler has already refused; the title guard's own branch, which is pinned as writing nothing
/// for the empty value but cannot be told apart from the write running with that value, because the
/// value it would write is the same as the create default; the order between the absolute rule and
/// the duplicate read, and between the guard and the reads, which no input can fail both at once —
/// pinned as pure logic by `FeedValidationTests`; the reference's localized strings for the rules
/// the port names by name, which `docs/parity.md` records; the wordings of the storage failures
/// this suite cannot trigger; and the transaction boundary the writes run inside.
@Suite struct GoogleReaderSubscriptionEditTests {
    private let routes = "/reader/api/0/subscription/"

    @Test func editReadsTheWholeListForSAndOneValueForA() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let feed = try await socket.seedFeed(try await socket.categoryID("All"), "https://e/1",
                "Feed", "", 0)

            // The second value of the list is the one the read cannot parse, so a patch that read
            // only the first — the answer the single-value read gives for the same name — passed
            // this input.
            #expect(try await socket.status("edit",
                pairs: ["s=feed/\(feed)", "s=bogus", "ac=unsubscribe"]) == .badRequest,
                "the guard, not the branch the read error reaches")
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(feed)", "s=bogus", "ac=unsubscribe"]) ==
                "{\"error_message\":\"googlereader: no valid stream IDs provided\"}",
                "the whole list is read, and the guard writes this for its two halves")

            // The same name read the other way: the single value is what this handler uses, so the
            // pair that puts an unparseable value second answers the write.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(feed)", "ac=edit", "a=user/-/label/Tech", "a=bogus"]) == "OK",
                "the single value, not the list")
            #expect(try await socket.categoryTitle(feed) == "Tech", "and the write happened")
        }
    }

    @Test func editStreamGuardReadsTheCountOfTheListAndNotTheEmptyValue() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // A name the form does not carry answers the empty list, so the guard reports it.
            // A name it carries with an empty value answers one stream — the read's own answer
            // for the empty value — so the guard passes and the integer read is what fails
            // here.
            #expect(try await socket.answer("edit", pairs: ["ac=unsubscribe"]) ==
                "{\"error_message\":\"googlereader: no valid stream IDs provided\"}",
                "the guard is on the count")
            #expect(try await socket.answer("edit", pairs: ["ac=unsubscribe", "s="]) ==
                "{\"error_message\":\"strconv.ParseInt: parsing \\\"\\\": invalid syntax\"}",
                "one stream read, and the read that cannot name an empty value")
        }
    }

    @Test func editRunsTheStreamGuardBeforeTheTagRead() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // Both halves fail on this input, so the answer names the one that runs first.
            #expect(try await socket.answer("edit", pairs: ["ac=subscribe", "a=bogus"]) ==
                "{\"error_message\":\"googlereader: no valid stream IDs provided\"}",
                "the order the reads run in")

            // The input where only the second half fails answers its wording.
            #expect(try await socket.answer("edit", pairs: ["s=feed/1", "ac=subscribe", "a=bogus"]) ==
                "{\"error_message\":\"googlereader: invalid data in a\"}", "the other half")
        }
    }

    @Test func editUsesThePresenceTestSoAnEmptyTagRunsTheMoveBranch() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let feed = try await socket.seedFeed(try await socket.categoryID("All"), "https://e/1",
                "Feed", "", 0)

            // The form carries the name with an empty value, so the branch runs and the type check
            // answers, where a read that compared the value with the empty string would have
            // skipped it.
            #expect(try await socket.answer("edit", pairs: ["s=feed/\(feed)", "ac=edit", "a="]) ==
                "{\"error_message\":\"destination must be a label\"}", "the name is there")

            // The same input without the name answers the write, and the rename half ran on it.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(feed)", "ac=edit", "t=Renamed"]) == "OK", "the name is not there")
            #expect(try await socket.feedTitle(feed) == "Renamed", "and that write happened")
            #expect(try await socket.categoryTitle(feed) == "All", "with no move")
        }
    }

    @Test func editRunsTheRenameBeforeTheTypeCheckAndTheTitleGuardBeforeBoth() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let feed = try await socket.seedFeed(try await socket.categoryID("All"), "https://e/1",
                "Feed", "", 0)

            // Both halves apply to this input: the row the stream names does not exist and the tag
            // is not a label, so the answer names the half that runs first.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/999", "ac=edit", "t=Title", "a=user/-/state/com.google/read"]) ==
                "{\"error_message\":\"googlereader: feed not found\"}", "the rename runs first")

            // The input where only the type check applies answers its wording, which is a third
            // wording naming the same kind of check — the two others are pinned by the
            // write-handler suite. The rename runs first, so its write is already there when the
            // check answers, and the title below is the value that write left.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(feed)", "ac=edit", "t=Title", "a=user/-/state/com.google/read"]) ==
                "{\"error_message\":\"destination must be a label\"}",
                "the check, on a row that is there")

            // The title guard is the empty value, so the rename does not run at all and nothing is
            // written: a patch that ran the rename for an empty title wrote its own guard's
            // wording, and the value the row holds here is the one the input above wrote.
            #expect(try await socket.answer("edit", pairs: ["s=feed/\(feed)", "ac=edit", "t="]) == "OK")
            #expect(try await socket.feedTitle(feed) == "Title", "nothing was written after the write")
        }
    }

    @Test func editActionSwitchWritesTheThreeBranchesAndNamesTheDefault() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let all = try await socket.categoryID("All")

            // The default case names the value it was given, and a name the form does not carry
            // answers the read's empty value, which is the same case.
            #expect(try await socket.answer("edit", pairs: ["s=feed/1", "ac=whatever"]) ==
                "{\"error_message\":\"googlereader: unrecognized action whatever\"}",
                "the default case names the value it was given")
            #expect(try await socket.answer("edit", pairs: ["s=feed/1", "ac="]) ==
                "{\"error_message\":\"googlereader: unrecognized action \"}",
                "and the empty value is the same case")

            // The three branches, each on its own row, so a patch that ran one branch for another
            // action cannot pass all three.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/https://e/new", "ac=subscribe", "t=New", "a=user/-/label/Tech"]) == "OK",
                "subscribe")
            let created = try #require(try await socket.feed("https://e/new"))
            let createdID = try #require(created.id)
            #expect(try await socket.categoryTitle(createdID) == "Tech",
                "the category the tag names, which did not exist before")
            #expect(try await socket.feedTitle(createdID) == "New",
                "and the title, written only when the value is not empty")

            let first = try await socket.seedFeed(all, "https://e/1", "Feed", "", 0)
            let second = try await socket.seedFeed(all, "https://e/2", "Other", "", 0)

            // The branch writes the row the first value names, which is the answer the pin above
            // reads for the whole list.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(first)", "s=feed/\(second)", "ac=edit",
                    "a=user/-/label/News"]) == "OK", "move")
            #expect(try await socket.categoryTitle(first) == "News", "the move")
            #expect(try await socket.categoryTitle(second) == "All", "and only the first row")

            // Every value of the list, not the first one, which is what a patch that read the
            // single value for this branch left behind.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/\(first)", "s=feed/\(second)", "ac=unsubscribe"]) == "OK", "unsubscribe")
            #expect(try await socket.feed("https://e/1") == nil, "both rows are gone")
            #expect(try await socket.feed("https://e/2") == nil, "and the second one")
        }
    }

    @Test func editMapsTheIntegerReadToTheServerErrorAndADeleteThatFindsNothingToTheWrite()
        async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // The same read answers 400 for `mark-all-as-read`, which is the pin the write-handler
            // suite holds; here it is the 500 this handler maps it to, with the read's own wording.
            // The status is read here too, so the pin can fail on the status the answer is written
            // under.
            #expect(try await socket.status("edit", pairs: ["s=feed/not-a-number", "ac=unsubscribe"]) ==
                .internalServerError, "the status this handler maps the read failure to")
            #expect(try await socket.answer("edit", pairs: ["s=feed/not-a-number", "ac=unsubscribe"]) ==
                "{\"error_message\":\"strconv.ParseInt: parsing \\\"not-a-number\\\": invalid syntax\"}")

            // The delete does not read the row first, so a stream naming a row that does not exist
            // answers the write, not the 404 the rename branch answers for a missing row.
            #expect(try await socket.answer("edit", pairs: ["s=feed/999", "ac=unsubscribe"]) == "OK",
                "no read before the write")
            #expect(try await socket.answer("edit", pairs: ["s=feed/999", "ac=edit", "t=Title"]) ==
                "{\"error_message\":\"googlereader: feed not found\"}", "and the read that does")
        }
    }

    @Test func subscribeReadsTheFirstCategoryWhenTheFormCarriesNoTag() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // The row the account creates is `All`, so the read has to be the one ordered by title
            // and not the one ordered by id: `AI` is the second row and the first under that order.
            let created = try await socket.categoryID("All")
            let lower = try await socket.seedCategory("AI")
            #expect(lower > created, "the id order is not the answer")

            #expect(try await socket.answer("edit",
                pairs: ["s=feed/https://e/new", "ac=subscribe"]) == "OK")
            let row = try #require(try await socket.feed("https://e/new"))
            let rowID = try #require(row.id)
            #expect(try await socket.categoryTitle(rowID) == "AI",
                "the read ordered by title, not the row that came first")
        }
    }

    @Test func subscribeNamesTheRuleTheInputFailsOnAndTheStatusItIsWrittenUnder() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let existing = try await socket.seedFeed(try await socket.categoryID("All"), "https://e/1",
                "Feed", "", 0)

            // The input fails the duplicate rule, and the category the tag names is created before
            // the validation reads it: a patch that ran the validation first answered the category
            // rule here, because the title the tag named did not have a row yet.
            #expect(try await socket.status("edit",
                pairs: ["s=feed/https://e/1", "ac=subscribe", "a=user/-/label/New"]) ==
                .internalServerError, "the status the rule name is written under")
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/https://e/1", "ac=subscribe", "a=user/-/label/New"]) ==
                "{\"error_message\":\"alreadyExists\"}",
                "the rule the input fails, read after the category was created")

            // The absolute rule is the rule this input fails on. The order between it and the
            // duplicate read cannot be pinned through the socket, because a url the duplicate read
            // can name is absolute, so no input fails both; the order is pinned as pure logic by
            // FeedValidationTests.
            #expect(try await socket.answer("edit", pairs: ["s=feed/example.org/x", "ac=subscribe"]) ==
                "{\"error_message\":\"invalidURL\"}", "the rule this input fails on")

            // The guard is the same kind of case: its value is empty, so no input fails both the
            // guard and a read, and a failing run writes nothing.
            #expect(try await socket.answer("edit", pairs: ["s=feed/", "ac=subscribe"]) ==
                "{\"error_message\":\"mandatoryFields\"}", "the rule the empty value fails on")
            #expect(try await socket.feed("https://e/1")?.id == existing, "nothing was written")
        }
    }
}
