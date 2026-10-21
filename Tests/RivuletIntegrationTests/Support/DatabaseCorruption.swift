import Foundation

/// Controlled damage for integrity tests: a real SQLite file that fails `quick_check`.
enum DatabaseCorruption {
    /// Overwrites the cell count of page 2 with 500 cells it does not have.
    ///
    /// Page 2 is the `_fluent_migrations` root in a migrated database, and it
    /// already holds the `SchemaV1` row. The page header starts with the page
    /// type, so the two-byte cell count lives at page offset 3.
    static func page2CellCount(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        var data = try Data(contentsOf: url)
        guard data.count > 4096 + 8 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data.replaceSubrange((4096 + 3)..<(4096 + 5), with: [0x01, 0xF4])
        try data.write(to: url)
    }
}
