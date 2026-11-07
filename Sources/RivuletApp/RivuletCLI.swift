import ConsoleKit
import Foundation
import RivuletCore

/// The Rivulet command-line interface.
///
/// The command set mirrors the final CLI surface: `serve`, `migrate`, `version`, `refresh`,
/// `status`, `create-admin`, `integration-credentials`, the feed commands `add`, `remove` and
/// `list`, and the maintenance commands `backup` and `vacuum` work; the remaining commands are
/// registered placeholders that report the stage implementing them (see `docs/plan/`).
public enum RivuletCLI {
    /// Runs the command named by `arguments`.
    ///
    /// `version` and `--help` never read the configuration or touch the database; every
    /// other command loads ``Config`` from `environment` first.
    ///
    /// - Parameters:
    /// - console: Console to print to and read input from (tests pass a capturing console).
    /// - environment: Environment variables used for configuration.
    /// - arguments: Raw arguments; the first element is the executable name.
    /// - space: The filesystem the runs read the room through; a test names the numbers it
    ///   reads, because the room of the machine this process runs on is not something a pin
    ///   can name.
    /// - verifier: The database the copy check reads through; a test names the problems it answers,
    ///   because the damage a real file has is not something a pin can name.
    /// - Throws: Errors from configuration, storage or the command itself. The executable
    ///   entry point reports them and exits with a non-zero status.
    public static func run(
        console: any Console,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        space: any FileSystemSpace = SystemFileSystemSpace(),
        verifier: any DatabaseVerifier = SystemDatabaseVerifier()
    ) async throws {
        try await console.run(
            Self.makeCommandGroup(environment: environment, space: space, verifier: verifier),
            input: CommandInput(arguments: arguments)
        )
    }

    /// Builds the top-level command group.
    ///
    /// - Parameters:
    /// - environment: Environment variables used for configuration.
    /// - space: The filesystem the free-space check reads.
    /// - verifier: The database the copy check reads.
    static func makeCommandGroup(environment: [String: String],
        space: any FileSystemSpace = SystemFileSystemSpace(),
        verifier: any DatabaseVerifier = SystemDatabaseVerifier()) -> any AsyncCommandGroup {
        var commands = AsyncCommands()
        commands.use(Serve(environment: environment), as: "serve")
        commands.use(Migrate(environment: environment), as: "migrate")
        commands.use(Version(), as: "version")
        commands.use(CreateAdmin(environment: environment), as: "create-admin")
        commands.use(IntegrationCredentials(environment: environment), as: "integration-credentials")
        commands.use(Refresh(environment: environment), as: "refresh")
        commands.use(Status(environment: environment), as: "status")
        commands.use(Add(environment: environment), as: "add")
        commands.use(Remove(environment: environment), as: "remove")
        commands.use(List(environment: environment), as: "list")
        commands.use(Backup(environment: environment, space: space, verifier: verifier), as: "backup")
        commands.use(Vacuum(environment: environment, space: space), as: "vacuum")
        for planned in Planned.all {
            commands.use(planned, as: planned.name)
        }
        return commands.group(help: "A lightweight, self-hosted feed reader.")
    }
}
