import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

/// Minimal proxy for the fetch integration tests, bound to port 0.
///
/// AsyncHTTPClient tunnels through a proxy with `CONNECT`, so the proxy has to answer the handshake
/// and then carry the response as raw bytes. This serves one canned response after the handshake,
/// which is enough to show that a proxied request is routed to the proxy rather than to the target.
final class StubProxy: Sendable {
    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let response: Data
    private let connectsLog: NIOLockedValueBox<[String]>

    /// The port the kernel assigned.
    let port: Int

    private init(
        group: MultiThreadedEventLoopGroup,
        channel: Channel,
        response: Data,
        connectsLog: NIOLockedValueBox<[String]>
    ) {
        self.group = group
        self.channel = channel
        self.response = response
        self.connectsLog = connectsLog
        self.port = channel.localAddress?.port ?? 0
    }

    /// Starts a proxy that answers `CONNECT` and then serves `response` on the tunnel.
    static func start(response: Data) async throws -> StubProxy {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let connectsLog = NIOLockedValueBox<[String]>([])

        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(StubProxyHandler(connects: connectsLog, response: response))
            }
            .bind(to: try SocketAddress(ipAddress: "127.0.0.1", port: 0))
            .get()

        return StubProxy(group: group, channel: channel, response: response, connectsLog: connectsLog)
    }

    /// Proxy URL for this proxy.
    var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Targets the proxy was asked to connect to, in arrival order.
    func connects() -> [String] {
        connectsLog.withLockedValue { $0 }
    }

    /// Stops the proxy.
    func stop() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }

    // One event loop thread per channel, so the handler's own state is not shared.
    private final class StubProxyHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer

        private let connectsLog: NIOLockedValueBox<[String]>
        private let response: Data
        private var handshakeDone = false

        init(connects: NIOLockedValueBox<[String]>, response: Data) {
            self.connectsLog = connects
            self.response = response
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            let request = String(decoding: buffer.readBytes(length: buffer.readableBytes) ?? [], as: UTF8.self)

            if !handshakeDone {
                // The first thing a proxy sees is the CONNECT request line, whose target is the
                // authority the client wants to reach.
                let target = request.dropFirst("CONNECT ".count).prefix(while: { $0 != " " && $0 != "\r" && $0 != "\n" })
                connectsLog.withLockedValue { $0.append(String(target)) }
                write(context, Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8))
                handshakeDone = true
                return
            }

            write(context, response)
        }

        private func write(_ context: ChannelHandlerContext, _ bytes: Data) {
            var buffer = context.channel.allocator.buffer(capacity: bytes.count)
            buffer.writeBytes(bytes)
            context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        }
    }
}
