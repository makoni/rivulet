import SwiftSoup

/// Plain-text extraction for `entries.content_text`, the FTS5-indexed column.
enum EntryText {
    /// Returns the visible text of `html` with whitespace collapsed.
    ///
    /// SwiftSoup drops script and style contents and decodes character
    /// references, so the index holds the words a reader would see. The input
    /// is used as is when it cannot be parsed, and the text is a best-effort
    /// index input either way: it is never rendered back to clients.
    static func plainText(fromHTML html: String) -> String {
        guard let document = try? SwiftSoup.parse(html) else {
            return html
        }
        return (try? document.text()) ?? html
    }
}
