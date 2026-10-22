import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

/// In-process HTTP server for the fetch integration tests.
///
/// Every test starts its own server bound to port 0 and reads the port the kernel assigned, so no
/// test depends on a fixed port. What a path answers is declared by the test, and the server keeps
/// no state beyond that table and the requests it received, which keeps behavior deterministic.
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

    /// The port the kernel assigned.
    let port: Int

    private init(
        group: MultiThreadedEventLoopGroup,
        channel: Channel,
        received: NIOLockedValueBox<[String: [Received]]>
    ) {
        self.group = group
        self.channel = channel
        self.received = received
        self.port = channel.localAddress?.port ?? 0
    }

    /// Starts a server that answers each path with its behavior.
    static func start(behaviors: [String: Behavior]) async throws -> StubFeedServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let received = NIOLockedValueBox<[String: [Received]]>([:])
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 0)

        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(StubHandler(behaviors: behaviors, received: received))
                }
            }
            .bind(to: address)
            .get()

        return StubFeedServer(group: group, channel: channel, received: received)
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

    /// Stops the server.
    func stop() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }

    // A NIO handler is used by its own event loop thread only, so its state is not shared;
    // `@unchecked Sendable` records that.
    private final class StubHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let behaviors: [String: Behavior]
        private let received: NIOLockedValueBox<[String: [Received]]>
        private var target = ""

        init(behaviors: [String: Behavior], received: NIOLockedValueBox<[String: [Received]]>) {
            self.behaviors = behaviors
            self.received = received
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

            channel.write(HTTPServerResponsePart.head(head), promise: nil)
            if !body.isEmpty {
                channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
            }
            channel.write(HTTPServerResponsePart.end(nil), promise: nil)
            channel.flush()
        }
    }
}
