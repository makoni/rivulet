import Glibc
import Testing

/// What the process adds, read as the events the child answers: the port the child bound to, the
/// response on the probed port, the exit code the signal path leaves, and the WAL the run's
/// shutdown leaves behind. The harness (`Support/SpawnedProcess.swift`) waits on events, never on a
/// timer, and kills the child on both paths.
///
/// What these pins can fail on, each checked by patching the production code, rebuilding the
/// binary, and reverting: that the built binary answers `serve` on the port the harness probed — a
/// binary that bound a port of its own answers a different port on the serve event, and the request
/// on the probed port answers as a connection failure; that the clean signal path exits with code
/// 0, which is the reference's clean-stop exit (`internal/cli/daemon.go` at commit `c4d54f87`
/// returns and `main.go` exits 1 only on an error); and that the WAL is empty after the clean exit,
/// which is what the run's shutdown leaves behind — a patch that skipped that shutdown left a
/// `-wal` file beside the database. These pins were green on the head before the wiring, because
/// their rules already held there; the red run for this PR is the absence of the wiring, recorded
/// as compile errors, so each pin here is shown to fail on the rule it names by patching the
/// wiring, not by absence.
///
/// What these pins cannot fail on: that the child exits at all — a patch that made the child never
/// exit hangs the exit pin until its time limit fires, which is the harness rule that an unbounded
/// wait carries a limit, not an answer the child gives, so the pins assert only the content a patch
/// can flip; a child that writes no line at all fails the pin through the harness, which answers
/// that read with no serve event, so it is not a fact the pin assumes; which part of the shutdown
/// emptied the WAL, because a clean close checkpoints and removes the file anyway, which is the
/// same reason the maintenance pins cannot read it; which line the harness reads as the serve
/// event, and the wording of the line, from which the pin reads only the port value; the choice of
/// port itself, which is the harness rule of no fixed ports and is read only as "the child answered
/// on exactly the probed port"; the kill on both paths, and whether the child was alive to receive
/// the signal, which the harness guarantees for the child it spawned, so the pin reads it as its
/// guard on the event rather than as a rule a patch to production code can flip; the order between
/// the server's stop and the shutdown hook inside the child, which nothing in the child answers on;
/// the wording of the lines and of the reported failures; that a signal arriving during a real
/// interval is answered before the interval ends, since no test can watch an hour pass, so this is
/// read as the event order (serve event, signal, exit) and recorded in `docs/parity.md`; and that
/// every picked job is written before the exit — the in-process wiring pins read that order through
/// the seams, while a process pin would have to wait for the loop to run, which is a timed wait.
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
}
