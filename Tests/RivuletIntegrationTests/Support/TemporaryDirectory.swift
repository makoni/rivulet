import Foundation

/// A unique temporary directory for a test.
///
/// Every test owns its directory (determinism rule in `docs/testing.md`) and removes it
/// in teardown via ``remove()``.
struct TemporaryDirectory {
    let url: URL

    /// Creates a fresh directory under the system temporary location.
    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rivulet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The path of `name` inside the directory.
    func path(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    /// Removes the directory and everything in it.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
