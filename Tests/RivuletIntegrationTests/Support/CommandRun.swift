import RivuletApp
@testable import RivuletCore

/// What one command run leaves behind: the output the console captured and whether the run failed.
struct RunOutcome: Sendable {
    let output: String
    let failed: Bool
}

/// Runs one command against the file the pin names, through the in-process console. The filesystem
/// the run reads is the seam the pin names, because the room a real filesystem has is the machine's
/// and cannot be named by a pin. The default answers enough room for anything, so the pins that do
/// not read the free-space check answer as they did before it. The check the run reads is the seam
/// the pin names for the same reason: the problems a real file has cannot be named by a pin, so the
/// default answers a clean check and the pins that do not read the verify step answer as they did
/// before it. The values pushed for the prompts are the answers the pins give the read, in the
/// order the run reaches them; a run that reads no prompt reads nothing pushed, which is what the
/// pins that push nothing rely on, and the order the two prompts are read in is not a rule any pin
/// can show.
func runCommand(databasePath: String, arguments: [String], inputs: [String] = [],
    environment: [String: String] = [:],
    space: any FileSystemSpace = RecordingSpace(sizes: [:], free: Int64.max),
    verifier: any DatabaseVerifier = RecordingVerifier(problems: [])) async throws -> RunOutcome {
    var values = environment
    values["DATABASE_URL"] = databasePath
    let console = TestConsole()
    for input in inputs {
        console.pushInput(input)
    }
    var failed = false
    do {
        try await RivuletCLI.run(console: console, environment: values,
            arguments: ["rivulet"] + arguments, space: space, verifier: verifier)
    } catch {
        failed = true
    }
    return RunOutcome(output: console.output, failed: failed)
}
