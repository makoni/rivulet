import Testing
@testable import RivuletCore

/// Plain-text extraction feeding the full-text index (`entries.content_text`).
@Suite struct EntryTextTests {
    @Test func plainTextKeepsTheVisibleWordsAndDropsTheMarkup() {
        let html = "<p>Hello&nbsp;<b>world</b></p><p>Second line</p>"
        #expect(EntryText.plainText(fromHTML: html) == "Hello world Second line")
    }

    @Test func plainTextDecodesCharacterReferences() {
        #expect(EntryText.plainText(fromHTML: "<p>Tom &amp; Jerry &lt;3</p>") == "Tom & Jerry <3")
    }

    @Test func plainTextDropsScriptAndStyleContents() {
        let html = "<style>p { color: red }</style><script>alert('x')</script><p>Visible</p>"
        #expect(EntryText.plainText(fromHTML: html) == "Visible")
    }

    @Test func plainTextCollapsesWhitespace() {
        #expect(EntryText.plainText(fromHTML: "<p>one\n\n   two\tthree</p>") == "one two three")
    }
}
