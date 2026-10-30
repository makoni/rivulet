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

    /// Reads a fixture as lines, which is how a corpus file is read. The trailing newline does not
    /// make an empty last line.
    static func lines(_ relativePath: String) throws -> [String] {
        String(data: try data(relativePath), encoding: .utf8).map {
            $0.split(separator: "\n").map { String($0) }
        } ?? []
    }

    /// Reads the bytes as UTF-8 for an assertion, without checking that they are valid UTF-8;
    /// the tests that mirror an upstream assertion also check validity, as upstream does.
    static func utf8(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Strict UTF-8 check, the reference's `utf8.Valid`.
    static func isValidUTF8(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8) != nil
    }
}
