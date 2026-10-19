import ConsoleKit
import RivuletCore

extension RivuletCLI {
    /// `rivulet version` — prints the version.
    struct Version: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        var help: String { "Prints the Rivulet version." }

        func run(using context: CommandContext, signature: Signature) async throws {
            context.console.print("rivulet \(RivuletCore.version)")
        }
    }
}
