import ConsoleKit
import Foundation

/// The Rivulet command-line interface.
///
/// The command set mirrors the final CLI surface: `serve`, `migrate` and `version` work;
/// the remaining commands are registered placeholders that report the stage implementing
/// them (see `docs/plan/`).
public enum RivuletCLI {
    /// Runs the command named by `arguments`.
    ///
    /// `version` and `--help` never read the configuration or touch the database; every
    /// other command loads ``Config`` from `environment` first.
    ///
    /// - Parameters:
    ///   - console: Console to print to and read input from (tests pass a capturing console).
    ///   - environment: Environment variables used for configuration.
    ///   - arguments: Raw arguments; the first element is the executable name.
    /// - Throws: Errors from configuration, storage or the command itself. The executable
    ///   entry point reports them and exits with a non-zero status.
    public static func run(
        console: any Console,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) async throws {
        try await console.run(
            Self.makeCommandGroup(environment: environment),
            input: CommandInput(arguments: arguments)
        )
    }

    /// Builds the top-level command group.
    static func makeCommandGroup(environment: [String: String]) -> any AsyncCommandGroup {
        var commands = AsyncCommands()
        commands.use(Serve(environment: environment), as: "serve")
        commands.use(Migrate(environment: environment), as: "migrate")
        commands.use(Version(), as: "version")
        for planned in Planned.all {
            commands.use(planned, as: planned.name)
        }
        return commands.group(help: "A lightweight, self-hosted feed reader.")
    }
}
