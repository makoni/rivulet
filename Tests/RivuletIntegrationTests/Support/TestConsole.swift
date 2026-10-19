import ConsoleKit
import Synchronization

/// An in-process console for command tests: captures everything written to it and replays
/// scripted input, so CLI commands can be exercised without a terminal.
///
/// See `docs/testing.md` (integration test infrastructure).
final class TestConsole: Console {
    private let outputLines = Mutex<[String]>([])
    private let inputQueue = Mutex<[String]>([])
    private let consoleUserInfo = Mutex<[AnySendableHashable: any Sendable]>([:])

    /// Everything written to the console (output and reported errors), concatenated in order.
    var output: String {
        outputLines.withLock { $0.joined() }
    }

    /// Queues a line to be returned by the next ``input(isSecure:)`` call.
    func pushInput(_ line: String) {
        inputQueue.withLock { $0.append(line) }
    }

    // MARK: - Console

    var size: (width: Int, height: Int) { (200, 50) }

    func input(isSecure: Bool) -> String {
        inputQueue.withLock { $0.isEmpty ? "" : $0.removeFirst() }
    }

    func output(_ text: ConsoleText, newLine: Bool) {
        outputLines.withLock { $0.append(text.description + (newLine ? "\n" : "")) }
    }

    func report(error: String, newLine: Bool) {
        outputLines.withLock { $0.append(error + (newLine ? "\n" : "")) }
    }

    func clear(_ type: ConsoleClear) {}

    var userInfo: [AnySendableHashable: any Sendable] {
        get { consoleUserInfo.withLock { $0 } }
        set { consoleUserInfo.withLock { $0 = newValue } }
    }
}
