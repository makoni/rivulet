import Foundation
import Testing
@testable import RivuletCore

/// The OPML write, ported from Miniflux `internal/reader/opml/serializer.go` at commit `c4d54f87`
/// (Apache-2.0). Each pin reads the one line or fragment the rule it names decides, so a probe that
/// patches one rule fails the pin that names it and no other. The round-trip pins at the end are
/// the ports of the upstream `serializer_test.go` cases; they read the writer through the values
/// handed to it, so the constants the build sets cannot reach them, and their records carry no
/// character the branch pins read and no miniflux value outside the set `ParseBool` accepts. What
/// these pins can fail on, each checked by patching the rule and reverting: the header line as the
/// constant the reference writes (`encoding="UTF-8"`, the case the pinned toolchain answers); the
/// root written at column 0; the four-space indent; the document ending at the root close with no
/// trailing newline; the layout rule that puts an element's close tag on its own line only when the
/// element wrote something, read through `body`; the version field written whatever the record
/// holds, because its tag has no `omitempty`; the namespace, the head fields, the `title` attribute
/// and the miniflux attributes written only when the record carries them, with `text` written
/// always and a false bool not written; the attribute order the field order gives; `type` written
/// last and only for a subscription; the escape set `EscapeString` reads, branch by branch and then
/// on the line the writer builds; the grouping keeping insertion order inside a category and the
/// sort rule ordering the categories as bytes; the three constants the document build gives; and
/// the date as the format the build applies to the time it is given, with the zone as the name the
/// port answers. The pins read whole-line values only for the rules they name, and read everything
/// else as a fragment without the leading indent, so a patch to the indent, the layout, the field
/// order or the escape set cannot reach a pin that does not name that rule. What these pins cannot
/// fail on: the reference formats the date with the local zone name while the port answers UTC, so
/// only the port's answer is pinnable here; the three constants the document build sets cannot be
/// told apart from writer-side hardcoding by any input, so the pins read them as values handed to
/// the build and the writer reads them as data; the control characters outside the nine the escape
/// pin reads; the newline before the root line, read as part of the element-layout rule rather than
/// as the header rule's constant; and the reference's other escape paths, which this write never
/// goes through: the exported `EscapeText`, which takes the newline flag as true and reads the same
/// set, and the `EncodeToken` chardata call, which takes it as false and leaves the newline as
/// written, with the CDATA branch that call opens for a value starting with `<![CDATA[`. What this
/// write reproduces is the printer path the encoder marshals string fields through.
@Suite struct OPMLSerializeTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private func lines(_ output: String) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func document(_ groups: [OPMLGroup], version: String = "2.0",
        namespace: String = "https://miniflux.app/opml", headerTitle: String = "Miniflux",
        dateCreated: String = "D", zoneName: String = "UTC") -> String {
        OPMLSerializer.serialize(OPMLDocumentShape(version: version, namespace: namespace,
            headerTitle: headerTitle, dateCreated: dateCreated, groups: groups), zoneName: zoneName)
    }

    @Test func theHeaderLineIsTheConstantTheReferenceWrites() {
        let out = lines(document([group("C", [oneUrl])]))
        #expect(out.first == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "the header as the constant the reference writes: \(out.first ?? "")")
    }

    @Test func theRootLineIsWrittenAtColumn0() {
        let out = lines(document([group("C", [oneUrl])]))
        #expect(out[1] == "<opml version=\"2.0\" xmlns:miniflux=\"https://miniflux.app/opml\">",
            "the root at column 0, not at the indent: \(out[1])")
    }

    @Test func theIndentIsFourSpaces() {
        let out = lines(document([group("C", [oneUrl])], headerTitle: "T"))
        #expect(out[2] == "    <head>", "the indent the encoder is configured with: \(out[2])")
    }

    @Test func theDocumentEndsAtTheRootCloseWithNoTrailingNewline() {
        // Read as the end of the document, not as a whole line, so a patch to the depth the root is
        // written at cannot reach this pin.
        let out = document([group("C", [oneUrl])])
        #expect(out.hasSuffix("</opml>"), "the document ends at the root close: \(out)")
        #expect(!out.hasSuffix("\n"), "and there is no trailing newline: \(out)")
    }

    @Test func anElementThatWritesNothingKeepsItsCloseTagOnTheSameLine() {
        // The layout rule, read through `body` on both halves: the element that writes nothing
        // keeps its close on the open line, and the element that writes something closes on its own
        // line. Reading it on `body` rather than on `head` is what keeps a patch to the head-field
        // rule from reaching this pin, because that patch makes the head write something for every
        // input.
        let empty = lines(document([]))
        #expect(empty.contains { $0.contains("<body></body>") },
            "the element that writes nothing: \(empty)")
        let withChild = lines(document([group("C", [oneUrl])]))
        #expect(withChild.contains { $0.contains("<body>") && !$0.contains("</body>") },
            "the element that writes something closes on its own line, not on the open one: \(withChild)")
    }

    @Test func theVersionIsWrittenWhateverTheRecordHolds() {
        // The version field has no `omitempty`, so the document that carries no version still
        // writes `version=""`.
        let out = lines(document([group("C", [oneUrl])], version: ""))
        #expect(out.contains { $0.contains("version=\"\"") },
            "the version half with no `omitempty`: \(out)")
    }

    @Test func theNamespaceIsWrittenOnlyWhenTheRecordCarriesOne() {
        let out = lines(document([group("C", [oneUrl])]))
        #expect(out.contains { $0.contains("xmlns:miniflux=\"https://miniflux.app/opml\"") },
            "the namespace as the field order gives it: \(out)")
        let empty = lines(document([group("C", [oneUrl])], namespace: ""))
        #expect(!empty.contains { $0.contains("xmlns:miniflux") },
            "the `omitempty` half: \(empty)")
    }

    @Test func theHeadFieldsAreWrittenOnlyWhenTheRecordCarriesThem() {
        // The writer half, read with explicit values so the constants pin below is the only pin
        // that reads the values the document build gives.
        let full = lines(document([group("C", [oneUrl])], headerTitle: "T"))
        #expect(full.contains { $0.contains("<title>T</title>") },
            "the field written when the record carries one: \(full)")
        #expect(full.contains { $0.contains("<dateCreated>D</dateCreated>") },
            "the date field written when the record carries one: \(full)")

        let noTitle = lines(document([group("C", [oneUrl])], headerTitle: ""))
        #expect(!noTitle.contains { $0.contains("<title>") },
            "the `omitempty` half of the head: \(noTitle)")
        #expect(!noTitle.contains { $0.contains("ownerName") },
            "a head field the record does not carry is not written: \(noTitle)")
    }

    @Test func theBuildSetsItsVersionConstant() {
        // The three constants the build sets cannot be told apart from writer-side hardcoding by
        // any input, so each is read as the value the build hands the writer, on its own pin.
        let built = lines(OPMLSerializer.serialize([oneUrl], now: OPMLSerializeTests.epoch))
        #expect(built.contains { $0.contains("version=\"2.0\"") },
            "the version as the build gives it: \(built)")
    }

    @Test func theBuildSetsItsNamespaceConstant() {
        let built = lines(OPMLSerializer.serialize([oneUrl], now: OPMLSerializeTests.epoch))
        #expect(built.contains { $0.contains("xmlns:miniflux=\"https://miniflux.app/opml\"") },
            "the namespace as the build gives it: \(built)")
    }

    @Test func theBuildSetsItsHeadTitleConstant() {
        let built = lines(OPMLSerializer.serialize([oneUrl], now: OPMLSerializeTests.epoch))
        #expect(built.contains { $0.contains("<title>Miniflux</title>") },
            "the head title as the build gives it: \(built)")
    }

    @Test func textIsAlwaysWritten() {
        let subscription = lines(document([group("Category 1", [oneUrl])]))
            .first { $0.contains("xmlUrl=\"http://e/1\"") }
        #expect(subscription?.contains("text=\"\"") == true,
            "the always-written half: \(subscription ?? "")")
    }

    @Test func titleIsWrittenOnlyWhenTheRecordCarriesIt() {
        let withoutTitle = lines(document([group("Category 1", [oneUrl])]))
            .first { $0.contains("xmlUrl=\"http://e/1\"") }
        #expect(withoutTitle?.contains("title=") == false, "the `omitempty` half: \(withoutTitle ?? "")")
        let withTitle = lines(document([group("Category 1", [OPMLSubscription(
            title: "T", feedURL: "http://e/2")])]))
            .first { $0.contains("xmlUrl=\"http://e/2\"") }
        #expect(withTitle?.contains("title=\"T\"") == true, "the half that writes it: \(withTitle ?? "")")
    }

    @Test func aFalseBoolIsNotWritten() {
        // The bool fields answer the empty value for false, so the attribute appears only for the
        // record that carries the true value.
        let withTrue = lines(document([group("Category 1", [OPMLSubscription(
            feedURL: "http://e/2", crawler: true)])]))
        #expect(withTrue.contains { $0.contains("miniflux:crawler=\"true\"") }, "\(withTrue)")
        let withFalse = lines(document([group("Category 1", [oneUrl])]))
        #expect(!withFalse.contains { $0.contains("crawler") },
            "the false value: \(withFalse)")
    }

    @Test func attributesAreWrittenInFieldOrder() throws {
        // The field order the reference writes: the format fields, then the miniflux names in the
        // order the model declares them, then `type`. Each fragment below names one group of the
        // order, so a patch that moves one group fails the fragment that names it.
        let record = OPMLSubscription(title: "Feed 1", feedURL: "http://example.org/feed/1",
            siteURL: "http://example.org/1", categoryName: "Category 1",
            scraperRules: "article.content", keeplistRules: "important", userAgent: "CustomAgent/1.0",
            crawler: true, fetchViaProxy: true)
        let out = lines(document([group("Category 1", [record])]))
        let line = try #require(out.first { $0.contains("xmlUrl=\"http://example.org/feed/1\"") })

        // The format fields in the order the model declares them, before the miniflux set.
        #expect(line.contains("title=\"Feed 1\" text=\"Feed 1\" xmlUrl=\"http://example.org/feed/1\" "
            + "htmlUrl=\"http://example.org/1\""), "the format fields: \(line)")
        // The miniflux names in the order the model declares them, with `keeplistRules` before the
        // names that follow it and `userAgent` after the filter names.
        #expect(line.contains("miniflux:scraperRules=\"article.content\" "
            + "miniflux:keeplistRules=\"important\" miniflux:userAgent=\"CustomAgent/1.0\" "
            + "miniflux:crawler=\"true\" miniflux:fetchViaProxy=\"true\""),
            "the miniflux names as the model declares them: \(line)")
        // `type` is the field the outline writer adds after all of them.
        #expect(line.contains("miniflux:fetchViaProxy=\"true\" type=\"rss\""),
            "the type last: \(line)")
    }

    @Test func typeIsWrittenOnlyForASubscription() {
        let out = lines(document([group("Category 1", [oneUrl])]))
        #expect(out.contains { $0.contains("type=\"rss\"") },
            "the subscription carries the type: \(out)")
        // The category line is read as a fragment without its `>`, so a patch that made another
        // field always written changes the line and cannot reach this pin.
        #expect(out.first { $0.contains("text=\"Category 1\"") }?.contains("type") == false,
            "the category outline answers the empty value: \(out)")
    }

    @Test func theValueIsEscapedAsTheEncoderEscapesIt() {
        // Each branch of the set read on its own input, so a patch that changes one branch fails
        // one assertion here, and the pin below that reads a whole line is the writer half that
        // applies the set to a value.
        #expect(OPMLSerializer.escape("a&b") == "a&amp;b", "the ampersand: \(OPMLSerializer.escape("a&b"))")
        #expect(OPMLSerializer.escape("a<b") == "a&lt;b", "the less-than: \(OPMLSerializer.escape("a<b"))")
        #expect(OPMLSerializer.escape("a>b") == "a&gt;b", "the greater-than: \(OPMLSerializer.escape("a>b"))")
        #expect(OPMLSerializer.escape("a\"b") == "a&#34;b", "the quote: \(OPMLSerializer.escape("a\"b"))")
        #expect(OPMLSerializer.escape("a'b") == "a&#39;b", "the apostrophe: \(OPMLSerializer.escape("a'b"))")
        #expect(OPMLSerializer.escape("a\tb") == "a&#x9;b", "the tab: \(OPMLSerializer.escape("a\tb"))")
        #expect(OPMLSerializer.escape("a\nb") == "a&#xA;b", "the newline: \(OPMLSerializer.escape("a\nb"))")
        #expect(OPMLSerializer.escape("a\rb") == "a&#xD;b", "the carriage return: \(OPMLSerializer.escape("a\rb"))")

        // The range half, read on its own: the three characters the switch names are in range, the
        // space is, and a control character outside them is not, which answers the replacement.
        #expect(OPMLSerializer.escape("a b") == "a b", "the space is in range and stays")
        #expect(OPMLSerializer.escape("a\u{01}b") == "a\u{FFFD}b",
            "outside the range: \(OPMLSerializer.escape("a\u{01}b"))")

        // The writer half: a value that carries the set reaches the line escaped, which is what
        // makes the newline round-trip through the read.
        let record = OPMLSubscription(title: "a&b\"c\td\ne", feedURL: "http://e/1",
            categoryName: "Category 1")
        let out = lines(document([group("Category 1", [record])]))
        #expect(out.contains { $0.contains("title=\"a&amp;b&#34;c&#x9;d&#xA;e\"") },
            "the escape on the line: \(out)")
        #expect(!out.contains { $0.contains("\td") },
            "the control characters are references, not raw bytes: \(out)")
    }

    @Test func categoriesAreSortedAsBytes() {
        // The names are sorted as bytes, which is what `sort.Strings` does, not as Swift compares a
        // String. `a` with a combining acute is canonically `á`, which Swift puts after `b` and the
        // bytes put before it. The groups are handed in the order that is neither the byte order
        // nor the insertion order, so a patch that stopped sorting fails this pin, and so does a
        // patch that sorted the way Swift compares.
        let first = OPMLSubscription(title: "F1", feedURL: "http://e/1", categoryName: "b")
        let second = OPMLSubscription(title: "F2", feedURL: "http://e/2", categoryName: "a\u{0301}")
        let out = lines(document([group("b", [first]), group("a\u{0301}", [second])]))
        #expect(out.firstIndex(where: { $0.contains("text=\"a\u{0301}\"") })!
            < out.firstIndex(where: { $0.contains("text=\"b\"") })!,
            "the byte order puts the combining name first, where Swift compares it after `b`: \(out)")
    }

    @Test func theGroupKeyIsTheNameAsBytesSoADecomposedNameIsItsOwnGroup() {
        // Read through the build, like the order pin: the group key is the build's own rule, so a
        // pin that hands the groups directly never runs it. `Café` and `Cafe` with a combining
        // acute are one name for Swift's `==` and two names as bytes, so a patch that compared the
        // key with `==` answered one group and failed this pin. The pin reads only that both groups
        // are written, so a patch to the order rule cannot reach it, and one record per name keeps
        // the order inside a category out of it.
        let out = lines(OPMLSerializer.serialize([
            OPMLSubscription(title: "F1", feedURL: "http://e/1", categoryName: "Café"),
            OPMLSubscription(title: "F2", feedURL: "http://e/1a", categoryName: "Cafe\u{0301}"),
        ], now: OPMLSerializeTests.epoch))
        // The names are read as bytes, not through `String.contains`, which compares canonically
        // and would answer the same line for both forms. The category lines are the ones without
        // `xmlUrl`.
        let categories = out.filter { $0.contains("Caf") && !$0.contains("xmlUrl=") }
        #expect(Set(categories.map { Array($0.utf8) }).count == 2,
            "the two names are not one name as bytes: \(out)")
    }

    @Test func groupingKeepsInsertionOrderInsideACategory() {
        // Read through the build, because the grouping rule is the build's own: a pin that reads
        // the shape directly cannot fail on a patch to the grouping. The two titles are in the
        // order that is not the byte order, so a patch that sorted inside the category answers
        // `F1a` first. Only one category is here, so the patch that sorted the categories cannot
        // reach this pin.
        let out = lines(OPMLSerializer.serialize([
            OPMLSubscription(title: "F1b", feedURL: "http://e/1", categoryName: "Category 1"),
            OPMLSubscription(title: "F1a", feedURL: "http://e/1a", categoryName: "Category 1"),
        ], now: OPMLSerializeTests.epoch))
        let linesOfRecords = out.filter { $0.contains("xmlUrl=") }
        #expect(linesOfRecords[0].contains("title=\"F1b\"") && linesOfRecords[1].contains("title=\"F1a\""),
            "the order the records arrived in: \(out)")
    }

    @Test func theDateFieldIsTheFormatTheBuildAppliesToTheTimeGiven() {
        // One pin for the date, because every patch to the format reaches the build path too: the
        // build reads the date as the layout answers it for the time it is given, through the zone
        // the port answers. The layout answers itself on its own reference time, the padded halves
        // read on the epoch, and the zone is the port's own against the reference's local zone
        // name, which no input can name here.
        let reference = Date(timeIntervalSince1970: 1136214245) // Mon, 02 Jan 2006 15:04:05 UTC
        #expect(OPMLSerializer.dateField(reference) == "Mon, 02 Jan 2006 15:04:05 UTC",
            "the layout answers itself on its own reference time")
        #expect(OPMLSerializer.dateField(OPMLSerializeTests.epoch) == "Thu, 01 Jan 1970 00:00:00 UTC",
            "the padded halves: the day is `01`, not `1`")
        let built = lines(OPMLSerializer.serialize([oneUrl], now: OPMLSerializeTests.epoch))
        #expect(built.contains { $0.contains("<dateCreated>Thu, 01 Jan 1970 00:00:00 UTC</dateCreated>") },
            "the date as the build reads it from the time: \(built)")
    }

    // MARK: - The upstream round-trip cases, ported

    @Test func theDocumentRoundTripsThroughTheRead() throws {
        // The records carry no miniflux setting and the site url is the same value as the feed url,
        // so the build constants and the title and site-url orders cannot reach this pin: it reads
        // the writer and the read through the values handed to them.
        let records = [
            OPMLSubscription(title: "Feed 1", feedURL: "http://example.org/feed/1",
                siteURL: "http://example.org/feed/1", categoryName: "Category 1"),
            OPMLSubscription(title: "Feed 2", feedURL: "http://example.org/feed/2",
                siteURL: "http://example.org/feed/2", categoryName: "Category 1"),
            OPMLSubscription(title: "Feed 3", feedURL: "http://example.org/feed/3",
                siteURL: "http://example.org/feed/3", categoryName: "Category 2"),
        ]

        // The upstream case also asserts the namespace string; that assertion lives on the
        // constants pin, so this pin reads only the round trip itself.
        let firstTwo = Array(records.prefix(2))
        let read = try OPMLParser.parse(Data(document([group("Category 1", firstTwo),
            group("Category 2", [records[2]])]).utf8))
        #expect(read == records, "the round trip reads back the records: \(read)")
    }

    @Test func theNewlineSurvivesTheRoundTripThroughTheRead() throws {
        // `TestSerializePreservesNewlinesInRules`. The newline is carried on a format field, so a
        // patch to the bool rule cannot reach this pin, and a patch to another branch of the escape
        // set cannot either, because the value reads back the same either way.
        let record = OPMLSubscription(title: "Feed 1", feedURL: "http://example.org/feed/1",
            siteURL: "http://example.org/feed/1", categoryName: "Category 1",
            description: "article.content\np.body")
        let read = try OPMLParser.parse(Data(document([group("Category 1", [record])]).utf8))
        #expect(read.first == record, "the newline comes back through the escape: \(read)")
    }

    @Test func settingsRoundTripThroughTheNamespace() throws {
        // The upstream `TestSerializeWithMinifluxSettings` half: the settings reach the record
        // through the namespace the document declares, and a setting the model has no field for is
        // not written. The values here are inside the set `ParseBool` accepts, so a patch that read
        // the string names through the bool rule answers the same record, and no value carries a
        // character the escape pins read.
        let record = OPMLSubscription(title: "Feed 1", feedURL: "http://example.org/feed/1",
            siteURL: "http://example.org/feed/1", categoryName: "Category 1",
            rewriteRules: "t", crawler: true, disabled: true)
        let output = document([group("Category 1", [record])])
        #expect(output.contains("miniflux:crawler=\"true\""), "written with the namespace: \(output)")
        #expect(!output.contains("cookie"), "a setting the model does not carry is not written")
        let read = try OPMLParser.parse(Data(output.utf8))
        #expect(read.first == record, "the settings come back: \(read)")
    }

    private func group(_ name: String, _ records: [OPMLSubscription]) -> OPMLGroup {
        OPMLGroup(name: name, subscriptions: records)
    }

    private var oneUrl: OPMLSubscription { OPMLSubscription(feedURL: "http://e/1") }
}
