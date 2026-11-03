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

        // Entry point of `AnyAsyncCommand`, overriding the default `AsyncCommand`
        // implementation: that one rejects leftover input, but natural invocations —
        // `rivulet add <url>`, `rivulet export feeds.opml` — must still report the stage.
        func run(using context: inout CommandContext) async throws {
            try await run(using: context, signature: Signature())
        }

        func run(using context: CommandContext, signature: Signature) async throws {
            throw CLIError("The `\(name)` command is not implemented yet (planned for stage \(stage)).")
        }
    }
}

extension RivuletCLI.Planned {
    /// Every planned command with the stage that implements it.
    ///
    /// `create-admin` is no longer here: the first slice of stage 5 landed it, and its pins are
    /// `CreateAdminTests`.
    static let all: [RivuletCLI.Planned] = [
        .init(name: "add", stage: 6),
        .init(name: "remove", stage: 6),
        .init(name: "list", stage: 6),
        .init(name: "import", stage: 5),
        .init(name: "export", stage: 5),
        .init(name: "integration-credentials", stage: 5),
        .init(name: "backup", stage: 6),
        .init(name: "vacuum", stage: 6),
    ]
}
