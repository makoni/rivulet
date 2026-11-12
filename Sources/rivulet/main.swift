import ConsoleKit
import RivuletApp

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// `EXIT_FAILURE` is a C macro, so Swift's importer exports it on glibc and Darwin but not on musl,
// where the name is not in scope at all. Both read 1, so the code the failing run exits with is
// named once here instead of read from the module, which keeps the answer the same on all three.
private let failureExitCode: Int32 = 1

let console = Terminal()
do {
    try await RivuletCLI.run(console: console)
} catch {
    console.report(error: "Error: \(error)", newLine: true)
    exit(failureExitCode)
}
