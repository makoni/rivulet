import RivuletApp
@testable import RivuletCore

/// What one command run leaves behind: the output the console captured and whether the run failed.
struct RunOutcome: Sendable {
    let output: String
    let failed: Bool
}

/// Runs one command against the file the pin names, through the in-process console.
///
/// The filesystem the run reads is the seam the pin names, because the room a real filesystem has
/// is the machine's and cannot be named by a pin. The default answers enough room for anything, so
/// the pins that do not read the free-space check answer as they did before it.
func runCommand(databasePath: String, arguments: [String],
    environment: [String: String] = [:],
    space: any FileSystemSpace = RecordingSpace(sizes: [:], free: Int64.max)) async throws -> RunOutcome {
    var values = environment
    values["DATABASE_URL"] = databasePath
    let console = TestConsole()
    var failed = false
    do {
        try await RivuletCLI.run(console: console, environment: values,
            arguments: ["rivulet"] + arguments, space: space)
    } catch {
        failed = true
    }
    return RunOutcome(output: console.output, failed: failed)
}
