import ConsoleKit
import Fluent
import RivuletCore
import Vapor

extension RivuletCLI {
    /// `rivulet serve` — runs the HTTP server and the cadence loop together.
    ///
    /// Reuses Vapor's built-in `ServeCommand` (through `Application.servers`): the default host and
    /// port come from `LISTEN_ADDR`, and the remaining arguments — `--hostname/-H`, `--port/-p`,
    /// `--bind/-b`, `--unix-socket` — are parsed by Vapor's command. Unsupported arguments are
    /// rejected before any database work. After the server is started the run builds the loop from
    /// the values the environment names and runs it to its end; the stop signal reaches the handler
    /// or the event as `ServerSignalSource` documents, the loop's decision answers on it, and the
    /// hook runs once after the loop, which is the position the reference's stop branch has.
    struct Serve: AnyAsyncCommand {
        let environment: [String: String]

        var help: String {
            "Runs the HTTP server (options: --hostname,-H; --port,-p; --bind,-b; --unix-socket)."
        }

        func outputHelp(using context: inout CommandContext) {
            context.console.print(
                "Usage: \(context.input.executable) [--hostname,-H] [--port,-p] [--bind,-b] [--unix-socket]"
            )
            context.console.print(help)
        }

        // `AnyAsyncCommand` directly: the default `AsyncCommand` entry point would reject the
        // remaining arguments, but those belong to Vapor's server command.
        func run(using context: inout CommandContext) async throws {
            try Self.validateArguments(context.input)

            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            do {
                try await rivulet.storage.prepare()
                // Verify integrity before migrations or any client request: serving a damaged file
                // can turn a recoverable backup into a lost database. The check stays after
                // `prepare()`: observed in testing, running it before the journal-mode change left
                // the pooled connection locked, so the shutdown checkpoint failed.
                try await rivulet.storage.quickCheck()
                rivulet.application.logger.notice("Database integrity check passed")
                if config.runMigrations {
                    try await rivulet.application.autoMigrate().get()
                } else {
                    rivulet.application.logger.notice("RUN_MIGRATIONS=false: skipping migrations")
                }
                try await rivulet.application.asyncBoot()

                var serverContext = CommandContext(console: context.console, input: context.input)
                serverContext.application = rivulet.application
                let serveCommand = await rivulet.application.servers.asyncCommand

                // The seams are built before the server command runs, so the signal handler the
                // source installs is in place while the server starts; the event it joins is the
                // one that command sets up, so the loop reads it after the command has returned.
                // The command starts the server and returns, so the loop is what keeps the run
                // alive: it runs to its end and the hook runs once after it, which is the rule
                // `ServeWiringTests` pins — the jobs a tick had started run before the shutdown, as
                // the reference holds it through `pool.Shutdown` in the stop branch.
                let clock = SystemClock()
                let fetcher = Fetcher(options: config.fetcher)
                let pipeline = RefreshPipeline(storage: rivulet.storage, fetcher: fetcher,
                    options: config.fetcher, nextCheck: NextCheckPolicy(), clock: clock)
                let signalSource = ServerSignalSource(rivulet.application)
                let wiring = ServeWiring(config: config, storage: rivulet.storage,
                    cadence: SystemCadence(signalSource: signalSource),
                    runner: pipeline, hook: ApplicationShutdownHook(rivulet: rivulet, fetcher: fetcher))

                try await serveCommand.run(using: &serverContext)
                try await wiring.run()
            } catch {
                // The hook is the run's single shutdown, so this path runs it only for the failure
                // that came before the hook — the startup reads or the server path. A hook that ran
                // has already run the shutdown once, and the caller owns exactly one call.
                try? await rivulet.shutdown()
                throw error
            }
        }

        /// Fails fast on arguments Vapor's `ServeCommand` does not accept, before this command
        /// touches the database.
        ///
        /// Vapor's command parses the same signature — but it runs after prepare, migrate and boot,
        /// and Fluent's boot-time scan reacts to `--auto-migrate`/`--auto-revert` before the error
        /// would surface. Parsing a copy here rejects such invocations while the database is still
        /// untouched.
        private static func validateArguments(_ input: CommandInput) throws {
            var probe = input
            _ = try ServeCommand.Signature(from: &probe)
            guard probe.arguments.isEmpty else {
                throw CommandError.unknownInput(probe.arguments.joined(separator: " "))
            }
        }
    }
}
