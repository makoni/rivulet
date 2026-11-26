import Foundation
import Glibc
import Testing

/// What the process adds, read as the events the child answers: the port the child bound to, the
/// response on the probed port, the exit code the signal path leaves, and the WAL the run's
/// shutdown leaves behind. The harness (`Support/SpawnedProcess.swift`) waits on events, never on a
/// timer, and kills the child on both paths.  What these pins can fail on, each checked by patching
/// the production code, rebuilding the binary, and reverting: that the built binary answers `serve`
/// on the port the harness probed — a binary that bound a port of its own answers a different port
/// on the serve event, and the request on the probed port answers as a connection failure; that the
/// clean signal path exits with code 0, which is the reference's clean-stop exit
/// (`internal/cli/daemon.go` at commit `c4d54f87` returns and `main.go` exits 1 only on an error);
/// and that the WAL is empty after the clean exit, which is what the run's shutdown leaves behind —
/// a patch that skipped that shutdown left a `-wal` file beside the database. These pins were green
/// on the head before the wiring, because their rules already held there; the red run for this PR
/// is the absence of the wiring, recorded as compile errors, so each pin here is shown to fail on
/// the rule it names by patching the wiring, not by absence.  What these pins cannot fail on: that
/// the child exits at all — a patch that made the child never exit hangs the exit pin until its
/// time limit fires, which is the harness rule that an unbounded wait carries a limit, not an
/// answer the child gives, so the pins assert only the content a patch can flip; a child that
/// writes no line at all fails the pin through the harness, which answers that read on the pin's own
/// cancellation, so the line is not a fact the pin assumes; the end of the stream is not a line at
/// all but the exit event, which is the rule the pin below names; which part of the shutdown emptied the WAL, because
/// a clean close checkpoints and removes the file anyway, which is the same reason the maintenance
/// pins cannot read it; which line the harness reads as the serve event, and the wording of the
/// line, from which the pin reads only the port value; the choice of port itself, which is the
/// harness rule of no fixed ports and is read only as "the child answered on exactly the probed
/// port"; the kill on both paths, and whether the child was alive to receive the signal, which the
/// harness guarantees for the child it spawned, so the pin reads it as its guard on the event
/// rather than as a rule a patch to production code can flip; the order between the server's stop
/// and the shutdown hook inside the child, which nothing in the child answers on; the wording of
/// the lines and of the reported failures; that a signal arriving during a real interval is
/// answered before the interval ends, since no test can watch an hour pass, so this is read as the
/// event order (serve event, signal, exit) and recorded in `docs/parity.md`; and that every picked
/// job is written before the exit — the in-process wiring pins read that order through the seams,
/// while the process pin below reads only that the loop reached its read at all, as the request the
/// stub answers, which is the one thing a process pin can read without a timed wait.  The pin that
/// reads the loop being reached names its rule, its failure shape and what it cannot show. Its rule
/// is that a serving run reaches the cadence read for the feed the pin seeds, read as the request
/// the child makes for it, the tick being the only path this pin's child fetches through: the pin
/// makes no request to the child, and the seed it writes is a command that fetches nothing. The pin
/// was green on the head, where that request came about a minute after the server started, and it
/// is shown to fail on the rule it names by patching the command so the wiring is not run: the
/// child answered no request, and the patch reverted byte-identically. The failure answers at the
/// pin's limit, which is the harness rule that an unbounded wait carries a limit and that the limit
/// counts only when the wait can answer at it — the arrival read is the read that answers the pin's
/// cancellation, so the limit is a failure and the harness still reaches the child. The pin asserts
/// two things — the arrival and the entry row the child wrote — while its `prepare` hook asserts two
/// more, the seed runs it names not having failed, which is the hook's own rule rather than the
/// pin's; both are read on the pin, so a patch to the hook's reads fires the pin as well. The pin
/// reads the signal and the exit as the events the harness documents rather than as rules of its
/// own, so no patch can fire it on the exit code the pin above already pins. What the pin cannot
/// show: the interval itself, since
/// no test can watch the minute the reference's minute type gives, so the pin names its own choice
/// of the smallest interval the config parses; that the row it reads came from the child's tick
/// rather than from a pass the pin made itself, which is why the pin seeds no entry row and reads
/// the file after the child is gone; that the seed was in place before the child started, which the
/// harness guarantees; and the row half on its own, because the write it reads belongs to the
/// pipeline, which its own suite pins, so that reach is reasoned there.  The pin that reads the end
/// of the stream names its rule, its failure shape and what it cannot show. Its rule is that the read
/// answers the exit the harness recorded for a child that exits before writing its serve line, rather
/// than the empty line that made the two answers the same shape: the patch that answered the end of
/// the stream as a line reported `noServeEvent` on this pin, and that patch reverted
/// byte-identically. The child this pin gives is the CLI's own error path, so the run reaches the
/// exit before the server starts and no database work is in it, and the status the pin reads is the
/// code the child answered for the input the pin gave. What this pin cannot show: that the child
/// exits at all, which is the harness rule named above; the other side of the rule, a child that has
/// written nothing and is still alive, which the pin's own cancellation answers and no patch to
/// production code can flip; and that the two reads answer the same status when the reader reaches the
/// exit event first, which is the harness's own record rather than an assertion — the run before this
/// change showed it, as the pins that read the exit answering `.noExitStatus` for a child the reader
/// had already reaped, which is why the exit read answers the record instead of asking for the child
/// again.
@Suite struct ServeProcessTests {
    @Test(.timeLimit(.minutes(2)))
    func theBuiltBinaryAnswersOnTheProbedPort() async throws {
        try await SpawnedProcess.withSpawnedProcess(env: [:],
            args: { port in ["serve", "--port", "\(port)"] }) { child in
            // The content the pin reads is the port the child bound to, not that a line exists: a
            // binary that ignored the argument answered a different port here. A pin that reads no
            // answer fails at its limit, which is the rule every unbounded wait carries a limit;
            // the request itself is bounded by the client's own default timeout, so it cannot hang.
            let bound = try await child.servePort()
            #expect(bound == child.port, "the port the child bound to: \(bound)")

            let status = try await child.response(path: "/healthz")
            #expect(status == 200, "the response the probed port answered: \(status)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func theCleanSignalPathExitsWithCodeZero() async throws {
        try await SpawnedProcess.withSpawnedProcess(env: [:],
            args: { port in ["serve", "--port", "\(port)"] }) { child in
            // The pin's own cancellation is what makes the limit a failure rather than a hang: the
            // harness answers a cancelled wait by killing the child, so a patch that never answers
            // the exit fails at the limit with no live process left behind. The serve event first,
            // so the pin reads the exit the serving path leaves, not the one the startup error path
            // leaves. The signal is read as the event the run ends on: a child that was already
            // gone answers false, so the exit is read as the signal's, not as one the child reached
            // on its own before the harness killed it.
            _ = try await child.servePort()
            #expect(child.send(signal: SIGTERM), "the child was alive to receive the signal")
            let status = try await child.waitExit()
            #expect(status == 0, "the exit code the clean signal path answered: \(status)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func theWalIsEmptyAfterTheCleanSignalExit() async throws {
        try await SpawnedProcess.withSpawnedProcess(env: [:],
            args: { port in ["serve", "--port", "\(port)"] }) { child in
            _ = try await child.servePort()
            #expect(child.send(signal: SIGTERM), "the child was alive to receive the signal")
            _ = try await child.waitExit()
            // The migrations wrote through the WAL, and the run's shutdown is what leaves nothing
            // behind: a patch that skipped the shutdown left the file, which is the rule the pin
            // names. Which part of the shutdown emptied it is not the pin's rule — a clean close
            // checkpoints and removes the WAL on its own, so a patch that dropped only the
            // checkpoint left this pin green, and the header names that.
            #expect(child.walIsEmpty(), "the WAL the child left behind")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func theReadThatReachesTheEndOfTheStreamAnswersTheExitNotNoEvent() async throws {
        // The child is the CLI's own error path: an argument Vapor's server command does not accept is
        // rejected before the database is touched, so the child writes its error line and exits before
        // the server starts. The stream ends with the child gone, and the read answers the status the
        // harness decoded for that exit rather than no serve event, which is the rule this pin names:
        // the patch that answered the end of the stream with the empty line — the shape that made the
        // two answers the same — reported `noServeEvent` here. The exit code is the child's own answer
        // for this input, the CLI's error exit. The other side of the rule, a child that has written
        // nothing and is still alive, is answered by the pin's own cancellation, which is the harness
        // rule the header names and no patch to production code can flip.
        try await SpawnedProcess.withSpawnedProcess(env: [:],
            args: { _ in ["serve", "--not-an-option"] }) { child in
            await #expect(throws: SpawnedProcessError.childExited(1)) {
                _ = try await child.servePort()
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func theServingRunReachesTheCadenceReadForADueFeed() async throws {
        // The document the pin declares for the feed it seeds. The fetch is the event the pin
        // reads, so the shape of the body is not part of the rule.
        let feedBody = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>pin feed</title><item><guid>pin-item</guid>
            <title>pin item</title></item></channel></rss>
            """.utf8)

        try await FetchTestSupport.withServer(
            behaviors: ["/feed.xml": StubFeedServer.Behavior(body: feedBody)]) { stub in
            try await SpawnedProcess.withSpawnedProcess(
                env: ["POLLING_FREQUENCY": "1", "FETCHER_ALLOW_PRIVATE_NETWORKS": "true"],
                args: { port in ["serve", "--port", "\(port)"] },
                prepare: { child in
                    // The rows the tick takes are the ones the pin seeds, through the commands that
                    // write them, before the child is spawned: `add` stamps the row with the
                    // instant the command ran, which the strict due rule takes at the next pass
                    // over the batch. The account name is the pin's own, so no other pin's seed is
                    // read here.
                    let account = try await runCommand(databasePath: child.databasePath,
                        arguments: ["create-admin"], inputs: ["cadence-pin", "cadence-pin-password"])
                    #expect(!account.failed, "the pin's account run failed: \(account.output)")
                    let seeded = try await runCommand(databasePath: child.databasePath,
                        arguments: ["add", stub.url("/feed.xml").absoluteString, "--user", "cadence-pin"])
                    #expect(!seeded.failed, "the pin's feed run failed: \(seeded.output)")
                }
            ) { child in
                _ = try await child.servePort()

                // The tick is the only path this pin's child fetches through, so the request the
                // stub answers is the loop's read. Shown to fail on that rule by patching the
                // command so the wiring is not run: no request arrived, and the wait answered at
                // its limit, which is the harness rule that an unbounded wait carries a limit.
                let arrived = await stub.waitForArrival(for: "/feed.xml")
                #expect(arrived, "the request the child made for the feed the pin seeded")

                // The rows are read with no connection of the child's open, so the pin ends the
                // child on the signal and reads the exit as the event the harness documents rather
                // than as a rule of its own — the pin above pins the exit code the clean signal
                // path leaves.
                _ = child.send(signal: SIGTERM)
                _ = try await child.waitExit()

                // The pin is not satisfied by the rows its own preparation wrote: the pin wrote the
                // feed row, and the entry below can only have been written by the child's tick.
                try await withMigratedStorage { database, _ in
                    let written = try await content(at: child.databasePath, on: database, as: "served")
                    #expect(written.entries.count == 1,
                        "the entry the child's tick wrote for the feed the pin seeded: \(written.entries)")
                }
            }
        }
    }
}
