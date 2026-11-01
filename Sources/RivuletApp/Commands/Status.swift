// The port's own command: Miniflux has no status command, so the shape is recorded in
// `docs/parity.md`, and `docs/plan/stage-6-cli.md` keeps it stable for monitoring and the soak.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet status` — the feed state, then exit.
    ///
    /// Reads the rows and the counts through the storage layer and prints them; it fetches nothing
    /// and sleeps nothing. `--json` selects the machine-readable document, whose keys are the
    /// column names the storage layer uses - `enabled` aside, which reports the `disabled` column
    /// as its positive form - so a script reading two runs can compare what changed. Without the
    /// flag the same values go to the console as lines, one per row, and the wording of those
    /// lines is the port's own.
    ///
    /// The due count is the batch's pick, read against the clock this command is built with: the
    /// system one, because a manual status report answers the state as it is now. The migrations
    /// run when `RUN_MIGRATIONS` is on, as `serve` has them gated, and this command does not run
    /// them when it is off; the reference checks that the schema is up to date on the daemon
    /// path, after the migrations and before the branch that runs the refresh pass, which this
    /// port does not port.
    struct Status: AsyncCommand {
        struct Signature: CommandSignature {
            /// Prints the machine-readable document instead of the console lines.
            @Flag(name: "json", help: "Print the machine-readable document")
            var json: Bool

            init() {}
        }

        let environment: [String: String]

        var help: String {
            "Reports the feed state: each row, its last fetch, errors and next check, and the counts."
        }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let snapshot: StatusSnapshot
            do {
                snapshot = try await rivulet.storage.withConnection { connection in
                    try await FeedRepository(connection).statusSnapshot(
                        now: SystemClock().now(), options: config.scheduler)
                }
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            if signature.json {
                let encoded = try JSONEncoder().encode(snapshot)
                context.console.print(String(decoding: encoded, as: UTF8.self))
            } else {
                printHumanForm(snapshot, to: context.console)
            }

            try await rivulet.shutdown()
        }

        /// The console form: one line per row with the values, then the counts. The words are the
        /// port's own, so the tests read the values on the line rather than the wording.
        private func printHumanForm(_ snapshot: StatusSnapshot, to console: any Console) {
            for feed in snapshot.feeds {
                let fetched = feed.fetchedAt.map(String.init) ?? "-"
                let next = feed.nextCheckAt.map(String.init) ?? "-"
                console.print("\(feed.id) \(feed.url) — fetched \(fetched), next \(next),"
                    + " errors \(feed.parsingErrorCount), \(feed.enabled ? "enabled" : "disabled")")
            }
            console.print("\(snapshot.totals.feeds) feed(s), \(snapshot.totals.enabled) enabled,"
                + " \(snapshot.totals.disabled) disabled, \(snapshot.totals.due) due,"
                + " \(snapshot.totals.atErrorLimit) at the error limit.")
        }
    }
}
