/// Resolves a host to addresses.
///
/// The seam exists so the address policy can be tested without a network: production uses the
/// system resolver, tests inject one. The fetcher resolves the host of a direct hop through this seam and
/// pins the client it builds to the address it validated, so the connection cannot be redirected by a
/// later lookup. A proxied hop is not resolved here: the proxy resolves the target.
public protocol AddressResolver: Sendable {
    /// Returns the addresses `host` resolves to, in the order the resolver answers.
    ///
    /// - Throws: ``FetchError/hostnameResolution(_:)`` when the name does not resolve.
    func resolve(host: String) async throws -> [NetworkAddress]
}
