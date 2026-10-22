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
