import Foundation

/// Controlled damage for integrity tests: a real SQLite file that fails `quick_check`.
enum DatabaseCorruption {
    /// Overwrites the cell count of page 2 with 500 cells it does not have.
    ///
    /// Page 2 is the `_fluent_migrations` root in a migrated database, and it already
    /// holds the `SchemaV1` row. The page size comes from the file header, and the page
    /// header starts with the page type, so the two-byte cell count lives at page
    /// offset 3.
    static func page2CellCount(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        var data = try Data(contentsOf: url)

        // Header bytes 16–17: page size as a power of two (1 means 65536).
        guard data.count > 17 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var pageSize = (Int(data[16]) << 8) | Int(data[17])
        if pageSize == 1 {
            pageSize = 65536
        }
        let cellCount = pageSize + 3
        guard pageSize >= 512, data.count > cellCount + 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        data.replaceSubrange(cellCount..<(cellCount + 2), with: [0x01, 0xF4])
        try data.write(to: url)
    }
}
