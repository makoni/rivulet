import Foundation

/// Size of `path` in bytes.
///
/// Throws when the file is missing or its metadata cannot be read: an assertion that a
/// WAL is empty must not be satisfied by a deleted file or by a failed stat.
func fileSize(_ path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let size = attributes[.size] as? NSNumber else {
        throw CocoaError(.fileReadUnknown)
    }
    return size.intValue
}
