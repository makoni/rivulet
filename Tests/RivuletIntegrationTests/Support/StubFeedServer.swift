import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

/// In-process HTTP server for the fetch integration tests.
///
/// Every test starts its own server bound to port 0 and reads the port the kernel assigned, so no
/// test depends on a fixed port. What a path answers is declared by the test, and the server keeps
/// no state beyond that table, the requests it received and the waiters a test registered on a path,
/// which keeps behavior deterministic.
/// A proxied request is recognized by its absolute request target, so the same server can play the
/// proxy for the proxy test.
final class StubFeedServer: Sendable {
    /// What one path answers. Plain types keep the tests free of NIO imports.
    struct Behavior {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        /// Serve the body as a gzip stream and say so.
        var gzip = false
        /// Wait this long before answering.
        var delay: Duration = .zero
        /// Send the head at once, then wait this long before the body. A test that passes on a timeout
        /// can use this to show the deadline covers body reading, not only the response head.
        var bodyDelay: Duration = .zero
        /// Close the connection without answering at all.
        var cutConnection = false
        /// Answer without `Content-Length`, which makes the transfer chunked.
        var chunked = false
    }

    /// A request the server received.
    struct Received {
        /// Request target as it arrived: a path for a direct request, the absolute URL when the
        /// request reached the server as a proxy.
        let target: String
        let headers: [String: String]
    }

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let received: NIOLockedValueBox<[String: [Received]]>
    private let arrivals: Arrivals

    /// The port the kernel assigned.
    let port: Int

    private init(
        group: MultiThreadedEventLoopGroup,
        channel: Channel,
        received: NIOLockedValueBox<[String: [Received]]>,
        arrivals: Arrivals
    ) {
        self.group = group
        self.channel = channel
        self.received = received
        self.arrivals = arrivals
        self.port = channel.localAddress?.port ?? 0
    }

    /// Starts a server that answers each path with its behavior.
    static func start(behaviors: [String: Behavior]) async throws -> StubFeedServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let received = NIOLockedValueBox<[String: [Received]]>([:])
        let arrivals = Arrivals()
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 0)

        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        StubHandler(behaviors: behaviors, received: received, arrivals: arrivals)
                    )
                }
            }
            .bind(to: address)
            .get()

        return StubFeedServer(group: group, channel: channel, received: received, arrivals: arrivals)
    }

    /// URL of `path` on this server.
    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path.hasPrefix("/") ? path : "/\(path)")")!
    }

    /// Server root, which is what a proxy URL for this server looks like.
    var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Requests received for `path`, in arrival order.
    func received(for path: String) -> [Received] {
        received.withLockedValue { $0[path] ?? [] }
    }

    /// Waits until a request for `path` has arrived.
    ///
    /// The check and the wait are one step under the lock, so a request that arrives in between is not
    /// missed. A test that has to act while a request is in flight waits here instead of sleeping.
    func waitForRequest(for path: String) async {
        await arrivals.wait(for: path)
    }

    /// Stops the server.
    func stop() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }

    /// Arrivals per path, with a way to wait for one without polling. The handler records a path as soon
    /// as the request head is read, which is after the fetcher took its client from the cache, so a test
    /// that waits here knows the client was in use when the head arrived. That holds only while the answer
    /// is still pending — a quick response releases the client before the test can act — which is why the
    /// cache test holds the body back.
    private final class Arrivals: Sendable {
        private struct State {
            var paths: [String: Int] = [:]
            var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
        }

        private let state = NIOLockedValueBox(State())

        func record(_ path: String) {
            let waiters: [CheckedContinuation<Void, Never>] = state.withLockedValue { state in
                state.paths[path, default: 0] += 1
                return state.waiters.removeValue(forKey: path) ?? []
            }
            for waiter in waiters {
                waiter.resume()
            }
        }

        func wait(for path: String) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let arrived = state.withLockedValue { state -> Bool in
                    guard state.paths[path] ?? 0 == 0 else {
                        return true
                    }
                    state.waiters[path, default: []].append(continuation)
                    return false
                }
                if arrived {
                    continuation.resume()
                }
            }
        }
    }

    // A NIO handler is used by its own event loop thread only, so its state is not shared;
    // `@unchecked Sendable` records that.
    private final class StubHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let behaviors: [String: Behavior]
        private let received: NIOLockedValueBox<[String: [Received]]>
        private let arrivals: Arrivals
        private var target = ""

        init(behaviors: [String: Behavior], received: NIOLockedValueBox<[String: [Received]]>, arrivals: Arrivals) {
            self.behaviors = behaviors
            self.received = received
            self.arrivals = arrivals
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let request):
                target = request.uri
                var headers: [String: String] = [:]
                for (name, value) in request.headers {
                    headers[name] = value
                }
                let path = URL(string: request.uri)?.path ?? request.uri
                received.withLockedValue { $0[path, default: []].append(Received(target: request.uri, headers: headers)) }
                arrivals.record(path)
            case .end:
                answer(context.channel, behaviors[pathKey] ?? Behavior())
            default:
                break
            }
        }

        // The lookup key is the path part of the target, so a proxied request answers like the
        // same path served directly.
        private var pathKey: String {
            URL(string: target)?.path ?? target
        }

        private func answer(_ channel: Channel, _ behavior: Behavior) {
            if behavior.cutConnection {
                channel.close(promise: nil)
                return
            }
            if behavior.delay > .zero {
                // `components.seconds` alone drops a sub-second delay, so the duration is converted
                // through attoseconds; the timing tests depend on a fraction of a second being real.
                let amount = TimeAmount.nanoseconds(Int64(behavior.delay.attoseconds / 1_000_000_000))
                channel.eventLoop.scheduleTask(in: amount) { self.write(channel, behavior) }
                return
            }
            self.write(channel, behavior)
        }

        private func write(_ channel: Channel, _ behavior: Behavior) {
            var head = HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: behavior.status)
            )
            for (name, value) in behavior.headers {
                head.headers.add(name: name, value: value)
            }

            let body = behavior.gzip ? GzipStream.compress(behavior.body) : behavior.body
            // Without a Content-Length the encoder answers with chunked transfer encoding.
            if !behavior.chunked {
                head.headers.add(name: "Content-Length", value: String(body.count))
            }

            var buffer = channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)

            channel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

            if body.isEmpty {
                channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                return
            }

            if behavior.bodyDelay > .zero {
                // The head is already on the wire, so the body arriving after the deadline is what the
                // timing test asks for. `components.seconds` alone would drop a sub-second duration.
                let amount = TimeAmount.nanoseconds(Int64(behavior.bodyDelay.attoseconds / 1_000_000_000))
                channel.eventLoop.scheduleTask(in: amount) { self.writeBody(channel, body) }
                return
            }

            writeBody(channel, body)
        }

        private func writeBody(_ channel: Channel, _ body: Data) {
            var buffer = channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
            channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
        }
    }
}
