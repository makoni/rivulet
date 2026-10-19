import ConsoleKit

extension RivuletCLI {
    /// A command that exists in the final CLI surface but is not implemented yet.
    struct Planned: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        /// Registered command name.
        let name: String

        /// Stage that implements the command (see `docs/plan/`).
        let stage: Int

        var help: String { "Arrives with stage \(stage)." }

        func run(using context: CommandContext, signature: Signature) async throws {
            throw CLIError("The `\(name)` command is not implemented yet (planned for stage \(stage)).")
        }
    }
}

extension RivuletCLI.Planned {
    /// Every planned command with the stage that implements it.
    static let all: [RivuletCLI.Planned] = [
        .init(name: "create-admin", stage: 5),
        .init(name: "add", stage: 6),
        .init(name: "remove", stage: 6),
        .init(name: "list", stage: 6),
        .init(name: "import", stage: 5),
        .init(name: "export", stage: 5),
        .init(name: "refresh", stage: 4),
        .init(name: "status", stage: 4),
        .init(name: "integration-credentials", stage: 5),
        .init(name: "backup", stage: 6),
        .init(name: "vacuum", stage: 6),
    ]
}
