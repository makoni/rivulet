import ConsoleKit
import RivuletApp

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

let console = Terminal()
do {
    try await RivuletCLI.run(console: console)
} catch {
    console.report(error: "Error: \(error)", newLine: true)
    exit(EXIT_FAILURE)
}
