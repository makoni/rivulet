#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

import Foundation

/// `getaddrinfo` hints. The C enum import differs between platforms — `SOCK_STREAM` is a struct on
/// Linux and an integer on Darwin — so the values are named once here.
private let streamSocketType: Int32 = {
    #if os(Linux)
    return Int32(SOCK_STREAM.rawValue)
    #else
    return SOCK_STREAM
    #endif
}()
private let tcpProtocol: Int32 = Int32(IPPROTO_TCP)

/// Resolves a host to addresses.
///
/// The seam exists so the address policy can be tested without a network: production uses the
/// system resolver, tests inject one. A fetch resolves a host once and then connects to the
/// validated address, so no second lookup happens during the request.
public protocol AddressResolver: Sendable {
    /// Returns the addresses `host` resolves to, in the order the resolver answers.
    ///
    /// - Throws: ``FetchError/hostnameResolution(_:)`` when the name does not resolve.
    func resolve(host: String) async throws -> [NetworkAddress]
}

/// The system resolver (`getaddrinfo`).
///
/// The libc call blocks, so it is not run on an event loop thread. This toolchain (Swift 6.4.1) has no
/// blocking-executor API — `withBlockingTaskExecutor` is not in scope — so the call runs on the
/// cooperative pool thread it is called from, which is what keeps an event loop free but is still a
/// blocking call; that is recorded here rather than worked around.
///
/// Its answer is validated once and pinned, which is what keeps the HTTP client from resolving the
/// name again. The hermetic suite cannot call it against a network, so its test uses a numeric host,
/// which `getaddrinfo` answers from the string itself without contacting anything.
public struct SystemAddressResolver: AddressResolver, Sendable {
    /// Creates a resolver.
    public init() {}

    /// Resolves `host` without a service name; only addresses are returned.
    public func resolve(host: String) async throws -> [NetworkAddress] {
        var hints = addrinfo()
        hints.ai_flags = 0
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = streamSocketType
        hints.ai_protocol = tcpProtocol

        var answers: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &answers) == 0 else {
            throw FetchError.hostnameResolution(host)
        }
        defer {
            if let answers {
                freeaddrinfo(answers)
            }
        }

        var addresses: [NetworkAddress] = []
        var entry = answers
        while let current = entry {
            if let address = addressBytes(from: current) {
                addresses.append(address)
            }
            entry = current.pointee.ai_next
        }
        return addresses
    }

    /// Reads the address bytes. The raw layout of `in_addr` and `in6_addr` is the address in
    /// network order, which is the order the canonical text form needs.
    private func addressBytes(from info: UnsafeMutablePointer<addrinfo>) -> NetworkAddress? {
        guard let socket = info.pointee.ai_addr else {
            return nil
        }
        switch Int32(info.pointee.ai_family) {
        case Int32(AF_INET):
            let bytes = socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                Array(withUnsafeBytes(of: $0.pointee.sin_addr) { $0 })
            }
            return bytes.count == 4 ? .ipv4(bytes) : nil
        case Int32(AF_INET6):
            let bytes = socket.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                Array(withUnsafeBytes(of: $0.pointee.sin6_addr) { $0 })
            }
            return bytes.count == 16 ? .ipv6(bytes) : nil
        default:
            return nil
        }
    }
}
