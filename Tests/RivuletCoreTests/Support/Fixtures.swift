import Foundation
import Testing

/// Access to the Miniflux fixture corpus copied under `Fixtures/` (see its README).
enum Fixtures {
    /// Loads a fixture by its path relative to the `Fixtures` directory, for example
    /// `"encoding/koi8r.xml"`.
    static func data(_ relativePath: String) throws -> Data {
        let url = try #require(
            Bundle.module.resourceURL?.appendingPathComponent("Fixtures/\(relativePath)"),
            "fixture not found: \(relativePath)"
        )
        return try Data(contentsOf: url)
    }

    /// Interprets bytes as UTF-8 for assertions.
    static func utf8(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }
}
