import AsyncHTTPClient
import Foundation
import Glibc

/// The process-level harness: spawns the built binary, reads events rather than time, and kills the
/// child on both paths, so a failing pin leaves no live process behind.
///
/// The built executable is the sibling of the test binary in `.build/debug`, which is where CI
/// leaves it after `swift build`. The rules this harness holds — the kill on both paths, the port
/// from the socket probe, the waits that answer on an event (a line the child writes, a response,
/// an exit) rather than on a timer, and the time limit every unbounded wait carries — are harness
/// rules, so no patch to production code can make a pin fail on them; `ServeProcessTests` names
/// them in its header and pins only what the process itself adds. A limit only counts when the wait
/// can answer the pin at the limit, so the exit and the line reads answer a cancelled pin as well,
/// which is the difference between a pin that fails at its limit and a run that hangs.
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
    private let stateLock = NSLock()
    private var lines: [String] = []
    private var lineWaiter: CheckedContinuation<String, Error>?
    private var lineCancelled = false
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

    /// The next line the child wrote, read as an event: nothing here waits on a timer. The check
    /// and the registration run under one lock with the exit state, so a line that arrives between
    /// them cannot be lost, and a child that writes nothing and ends answers the read with the
    /// empty line the pin names. A wait answers on its own cancellation only when nothing else can
    /// answer it, which is what a pin's time limit needs: a patch that leaves the child silent
    /// fails at the limit.
    func line() async throws -> String {
        return try await withTaskCancellationHandler(handler: {
            cancelLineRead()
        }, operation: {
            try await withCheckedThrowingContinuation { (continuation:
                CheckedContinuation<String, Error>) in
                stateLock.lock()
                if !lines.isEmpty {
                    let line = lines.removeFirst()
                    stateLock.unlock()
                    continuation.resume(returning: line)
                    return
                }
                if outputClosed {
                    stateLock.unlock()
                    continuation.resume(returning: "")
                    return
                }
                if lineCancelled {
                    stateLock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                lineWaiter = continuation
                stateLock.unlock()
            }
        })
    }

    /// A line read that is cancelled is answered as the cancellation, and the child is killed so it
    /// does not outlive the pin that asked for it.
    private func cancelLineRead() {
        stateLock.lock()
        lineCancelled = true
        if let waiter = lineWaiter {
            lineWaiter = nil
            stateLock.unlock()
            killChild()
            waiter.resume(throwing: CancellationError())
        } else {
            stateLock.unlock()
        }
    }

    /// The serve event: the first line that names a port, read as the port the child bound to.
    /// Which line is recognised as the serve event is the harness's rule; the pin reads only the
    /// value, which a patch to the port the server uses changes.
    func servePort() async throws -> Int {
        while true {
            let line = try await line()
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
    /// so the child is listening when the request goes out. The client carries its own default
    /// timeout of 30 seconds, so a request that no child answers fails on that bound rather than
    /// hanging, which is the rule an unbounded wait carries a limit; the pins carry their own limit
    /// as well.
    func response(path: String) async throws -> Int {
        let client = HTTPClient()
        let response = try await client.execute(
            request: HTTPClient.Request(url: "http://127.0.0.1:\(port)\(path)")
        ).get()
        try await client.shutdown()
        return Int(response.status.code)
    }

    /// The event that the child is gone, read as the status the harness decoded: 0..127 is the exit
    /// code, and `128 + n` names the signal that ended it. The wait answers on the exit event, not
    /// on a timer, and the poll loop runs in the pin's own task context so the pin's time limit can
    /// fire on a child that never exits — a limit that could not fire would only rename a hang, and
    /// the harness needs to be able to fail a pin, not wait forever for it. A normal run answers on
    /// the first check, because the child is already gone when the harness asks; the interval is
    /// the harness's own poll bound, not a wait a pin names, and no pin asserts anything from it.
    func waitExit() async throws -> Int32 {
        let status = try await withCheckedThrowingContinuation { (continuation:
            CheckedContinuation<Int32, Error>) in
            while true {
                let ended = waitpid(pid, &rawStatus, WNOHANG)
                if ended > 0 {
                    stateLock.lock()
                    reaped = true
                    stateLock.unlock()
                    continuation.resume(returning: status(of: rawStatus))
                    return
                }
                if ended < 0 {
                    // The child is gone with no status the pins could name.
                    continuation.resume(throwing: SpawnedProcessError.noExitStatus)
                    return
                }
                if Task.isCancelled {
                    // The pin is gone, so the child must not outlive it.
                    killChild()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                usleep(pollInterval)
            }
        }
        return status
    }

    private var rawStatus: Int32 = 0

    /// The harness's poll bound: 50 ms between checks for the exit event and for the pin's
    /// cancellation, so the loop is not a hot spin. Nothing a pin reads comes from this value.
    private let pollInterval: UInt32 = 50_000

    private func status(of raw: Int32) -> Int32 {
        if raw & 0x7f == 0 { return (raw >> 8) & 0x7f }
        return 128 + (raw & 0x7f)
    }

    /// Sends the signal the pin names to the child, without waiting for anything, and answers
    /// whether the child was alive to receive it. A child that was already gone answers `false`, so
    /// a pin can read that the signal is what ended the run rather than an exit the child reached
    /// on its own.
    func send(signal: Int32) -> Bool {
        return Glibc.kill(pid, signal) == 0
    }

    /// The WAL file the child left behind, read after the exit event: nothing left uncheckpointed,
    /// read as the file being empty or absent. Absence is the fact a clean close leaves, because
    /// SQLite removes the `-wal` file when the last connection closes, so this is the one place
    /// where the rule of `FileSize.swift` — an assertion that a WAL is empty cannot be satisfied by
    /// a deleted file — does not apply, and the pin names that in its header.
    func walIsEmpty() -> Bool {
        let wal = databasePath + "-wal"
        guard FileManager.default.fileExists(atPath: wal) else { return true }
        return (try? fileSize(wal)) == 0
    }

    /// The child is only signalled when it was actually spawned: with no child, `kill(0, …)`
    /// signals the caller's process group, which would kill the test runner.
    private func killChild() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if reaped || pid == 0 { return }
        Glibc.kill(pid, SIGKILL)
    }

    private func reap() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if reaped || pid == 0 { return }
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

        // The parent's copy of the write end is closed at once: the reader sees the end of the
        // stream when the child is gone, which is the event that answers a read for a line that
        // never came.
        close(outputPipe[1])
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
        stateLock.lock()
        if let waiter = lineWaiter {
            lineWaiter = nil
            stateLock.unlock()
            waiter.resume(returning: line)
        } else {
            lines.append(line)
            stateLock.unlock()
        }
    }

    /// The end of the stream: only the read end is still open here, because the parent closed its
    /// copy of the write end at spawn, so this is reached when the child is gone.
    private func closeOutput() {
        stateLock.lock()
        outputClosed = true
        let waiter = lineWaiter
        lineWaiter = nil
        stateLock.unlock()

        close(outputPipe[0])
        if let waiter = waiter {
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
    case noExitStatus
}
