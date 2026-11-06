import AsyncHTTPClient
import Foundation
import Glibc

/// The process-level harness: spawns the built binary, reads events rather than time, and kills the
/// child on both paths, so a failing pin leaves no live process behind.
///
/// The built executable is the sibling of the test binary in `.build/debug`, which is where CI
/// leaves it after `swift build`. The rules this harness holds — the kill on both paths, the port
/// from the socket probe, the waits that answer on an event (a line the child writes, a response,
/// an exit) rather than on a timer — are harness rules, so no patch to production code can make a
/// pin fail on them; `ServeProcessTests` names them in its header and pins only what the process
/// itself adds.
///
/// The child's output is read through a pipe as an event stream, and the line that names a port is
/// the serve event the pins read. Recognising that line is the harness's rule, not a pin: the pin
/// reads the port value off it, so a binary that bound a port of its own answers a different value.
final class SpawnedProcess: @unchecked Sendable {
    /// The pin env and args the child is spawned with; the harness adds `DATABASE_URL` with the
    /// temp file path so every pin names the file it reads after the run.
    private let env: [String: String]
    private let args: [String]

    /// The SQLite file the child writes to, in a fresh temp dir, and the port from the probe.
    let databasePath: String
    let port: Int

    private let tempDir: TemporaryDirectory
    private let outputPipe: [Int32]
    private var lines: [String] = []
    private var lineWaiter: CheckedContinuation<String, Never>?
    private var outputClosed = false
    private var pid: Int32 = 0
    private var reaped = false

    /// Runs `body` with the child spawned, and guarantees the child is dead after the run. The
    /// signal path is the pins' own, so the harness only guarantees the teardown: the child is
    /// killed on the failure path, and on the success path when a pin did not read its exit.
    static func withSpawnedProcess(
        env: [String: String],
        args: (Int) -> [String],
        _ body: (SpawnedProcess) async throws -> Void
    ) async throws {
        let harness = try SpawnedProcess(env: env, args: args)
        do {
            try harness.spawn()
            harness.startReader()
            try await body(harness)
        } catch {
            harness.killChild()
            harness.reap()
            throw error
        }
        if !harness.reaped {
            harness.killChild()
            harness.reap()
        }
        harness.cleanUp()
    }

    private init(env: [String: String], args: (Int) -> [String]) throws {
        let dir = try TemporaryDirectory()
        let probePort = try SpawnedProcess.probeEphemeralPort()
        let pipe = try SpawnedProcess.makePipe()
        var childEnv = env
        childEnv["DATABASE_URL"] = dir.path("test.sqlite")
        tempDir = dir
        databasePath = dir.path("test.sqlite")
        port = probePort
        outputPipe = pipe
        self.env = childEnv
        self.args = args(port)
    }

    /// The next line the child wrote, read as an event: nothing here waits on a timer.
    func line() async -> String {
        if !lines.isEmpty { return lines.removeFirst() }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            if outputClosed {
                continuation.resume(returning: "")
                return
            }
            lineWaiter = continuation
        }
    }

    /// The serve event: the first line that names a port, read as the port the child bound to.
    /// Which line is recognised as the serve event is the harness's rule; the pin reads only the
    /// value, which a patch to the port the server uses changes.
    func servePort() async throws -> Int {
        while true {
            let line = await line()
            if line.isEmpty {
                throw SpawnedProcessError.noServeEvent
            }
            if let named = SpawnedProcess.portIn(line) {
                return named
            }
        }
    }

    /// The response event the pin reads on the probed port. No timeout is applied by the harness:
    /// the request answers when the child answers, and the pins read it only after the serve event,
    /// so the child is listening when the request goes out.
    func response(path: String) async throws -> Int {
        let client = HTTPClient()
        let response = try await client.execute(
            request: HTTPClient.Request(url: "http://127.0.0.1:\(port)\(path)")
        ).get()
        try await client.shutdown()
        return Int(response.status.code)
    }

    /// The event that the child is gone, read as the status the harness decoded: 0..127 is the exit
    /// code, and `128 + n` names the signal that ended it. This wait answers on the exit event, not
    /// on a timer.
    func waitExit() async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            DispatchQueue.global().async {
                var raw: Int32 = 0
                let ended = waitpid(self.pid, &raw, 0)
                self.reaped = true
                if ended < 0 {
                    // The child is gone with no status the pins could name.
                    continuation.resume(returning: -1)
                    return
                }
                if raw & 0x7f == 0 {
                    continuation.resume(returning: (raw >> 8) & 0x7f)
                } else {
                    continuation.resume(returning: 128 + (raw & 0x7f))
                }
            }
        }
    }

    /// Sends the signal the pin names to the child, without waiting for anything.
    func send(signal: Int32) {
        Glibc.kill(pid, signal)
    }

    /// The WAL file the child left behind, read after the exit event: empty or absent is the fact
    /// the pin names, because nothing was left uncheckpointed.
    func walIsEmpty() -> Bool {
        let wal = databasePath + "-wal"
        guard FileManager.default.fileExists(atPath: wal) else { return true }
        let size = (try? FileManager.default.attributesOfItem(atPath: wal)[.size] as? Int) ?? 0
        return size == 0
    }

    private func killChild() {
        if reaped { return }
        Glibc.kill(pid, SIGKILL)
    }

    private func reap() {
        if reaped { return }
        var raw: Int32 = 0
        _ = waitpid(pid, &raw, 0)
        reaped = true
    }

    private func spawn() throws {
        let binary = SpawnedProcess.resolveBuiltBinary()
        var attributes = posix_spawnattr_t()
        posix_spawnattr_init(&attributes)

        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        // The child's output goes to the pipe the pins read lines from.
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], 2)

        let envStrings = env.map { "\($0.key)=\($0.value)" }
        var envp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        envp.append(nil)
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(binary)] + args.map { strdup($0) }
        argv.append(nil)

        let result = posix_spawn(&pid, binary, &actions, &attributes, argv, envp)
        if result != 0 {
            throw SpawnedProcessError.spawnFailed(result)
        }
    }

    private func startReader() {
        DispatchQueue.global().async {
            var pending = ""
            while true {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = read(self.outputPipe[0], &buffer, buffer.count)
                if count <= 0 { break }
                pending += String(decoding: buffer[0..<count], as: UTF8.self)
                while let breakAt = pending.firstIndex(of: "\n") {
                    let line = String(pending[pending.startIndex..<breakAt])
                    pending = String(pending[pending.index(after: breakAt)...])
                    self.deliver(line)
                }
            }
            self.closeOutput()
        }
    }

    private func deliver(_ line: String) {
        if let waiter = lineWaiter {
            lineWaiter = nil
            waiter.resume(returning: line)
        } else {
            lines.append(line)
        }
    }

    private func closeOutput() {
        outputClosed = true
        close(outputPipe[0])
        close(outputPipe[1])
        if let waiter = lineWaiter {
            lineWaiter = nil
            waiter.resume(returning: "")
        }
    }

    private func cleanUp() {
        tempDir.remove()
    }

    /// The child binary is the sibling of the test binary; the pins run the built executable, not a
    /// recompile.
    private static func resolveBuiltBinary() -> String {
        let testBinary = CommandLine.arguments[0]
        return (testBinary as NSString).deletingLastPathComponent + "/rivulet"
    }

    /// The port comes from the socket probe, never from a fixed number: bind port 0, read what the
    /// system answers, close, and hand that port to the child.
    private static func probeEphemeralPort() throws -> Int {
        let probe = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        if probe < 0 { throw SpawnedProcessError.probeFailed }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        func bindTo(_ name: inout sockaddr_in) -> Int32 {
            withUnsafePointer(to: &name) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        func readName(_ name: inout sockaddr_in) -> Int32 {
            withUnsafeMutablePointer(to: &name) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                    return getsockname(probe, $0, &length)
                }
            }
        }

        if bindTo(&address) != 0 {
            close(probe)
            throw SpawnedProcessError.probeFailed
        }
        var name = sockaddr_in()
        if readName(&name) != 0 {
            close(probe)
            throw SpawnedProcessError.probeFailed
        }
        close(probe)
        return Int(ntohs(name.sin_port))
    }

    private static func makePipe() throws -> [Int32] {
        var fds: [Int32] = [0, 0]
        if pipe(&fds) != 0 { throw SpawnedProcessError.pipeFailed }
        return fds
    }

    /// The port a line names, as the harness reads it: the digits after the last colon.
    private static func portIn(_ line: String) -> Int? {
        guard let colon = line.lastIndex(of: ":") else { return nil }
        let tail = line[line.index(after: colon)...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(tail)
    }
}

enum SpawnedProcessError: Error, Equatable {
    case spawnFailed(Int32)
    case probeFailed
    case pipeFailed
    case noServeEvent
}
