import Foundation

/// Controlled damage for integrity tests: a real SQLite file that fails `quick_check`.
enum DatabaseCorruption {
    /// Damages the cell-count field of page 2 (the `users` root): the page claims
    /// 500 cells it does not have, which `PRAGMA quick_check` reports. Seed a user
    /// first so page 2 carries a real cell.
    static func page2CellCount(at path: String) {
        guard var data = (try? Data(contentsOf: URL(fileURLWithPath: path))),
              data.count > 4096 + 8 else {
            return
        }
        data.replaceSubrange((4096 + 4)..<(4096 + 8), with: [0, 0, 0x01, 0xF4])
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
