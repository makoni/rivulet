import ConsoleKit
import Fluent
import RivuletCore
import Vapor

extension RivuletCLI {
    /// `rivulet serve` — runs the HTTP server.
    ///
    /// Reuses Vapor's built-in `ServeCommand` (through `Application.servers`): the default
    /// host and port come from `LISTEN_ADDR`, and the remaining arguments — `--hostname/-H`,
    /// `--port/-p`, `--bind/-b`, `--unix-socket` — are parsed by Vapor's command. Unsupported
    /// arguments are rejected before any database work. Returns when the process receives
    /// `SIGINT`/`SIGTERM`.
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

        // `AnyAsyncCommand` directly: the default `AsyncCommand` entry point would reject
        // the remaining arguments, but those belong to Vapor's server command.
        func run(using context: inout CommandContext) async throws {
            try Self.validateArguments(context.input)

            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            do {
                try await rivulet.storage.prepare()
                // Verify integrity before migrations or any client request: serving a
                // damaged file can turn a recoverable backup into a lost database.
                // The check stays after `prepare()`: observed in testing, running it
                // before the journal-mode change left the pooled connection locked, so
                // the shutdown checkpoint failed.
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
                try await serveCommand.run(using: &serverContext)
                try await rivulet.application.running?.onStop.get()
            } catch {
                try? await rivulet.shutdown()
                throw error
            }
            try await rivulet.shutdown()
        }

        /// Fails fast on arguments Vapor's `ServeCommand` does not accept, before this
        /// command touches the database.
        ///
        /// Vapor's command parses the same signature — but it runs after prepare, migrate
        /// and boot, and Fluent's boot-time scan reacts to `--auto-migrate`/`--auto-revert`
        /// before the error would surface. Parsing a copy here rejects such invocations
        /// while the database is still untouched.
        private static func validateArguments(_ input: CommandInput) throws {
            var probe = input
            _ = try ServeCommand.Signature(from: &probe)
            guard probe.arguments.isEmpty else {
                throw CommandError.unknownInput(probe.arguments.joined(separator: " "))
            }
        }
    }
}
