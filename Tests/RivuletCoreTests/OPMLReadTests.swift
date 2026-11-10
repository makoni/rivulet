import Foundation
import Testing
@testable import RivuletCore

/// The OPML read, ported from Miniflux `internal/reader/opml` at commit `c4d54f87` (Apache-2.0):
/// the shape the document model matches, the values the outline fields read, and the name set the
/// miniflux attributes pass. The read here is over the tokens the tolerant reader already builds;
/// the reference's value layer (`UnmarshalXML`) has no port counterpart, so the shape rules below
/// are read as the reference reads them and the record is assembled from the tree. The flags the
/// reference's decoder is configured with (`Entity = xml.HTMLEntity`, `Strict = false`,
/// `CharsetReader`) are the tokenizer's rules, pinned by its own suites; what this suite can show
/// is only that the values reach the record as the tokens read them. Each pin names one rule, so a
/// probe that patches one rule fails the pin that names it and no other: the miniflux value a pin
/// reads is one the bool rule accepts wherever the pin does not name that rule, and no outline
/// carries a `type` value except the pin that names the branch. What these pins can fail on, each
/// checked by patching the rule and reverting: the root name the model tags, which the reference
/// checks even with `Strict = false`; the read failure reaching as a failure rather than an empty
/// document; that outlines are read only as direct children of `body`, which a patch that read the
/// whole tree fails on; that the branch is the url value alone, which a patch that read the `type`
/// attribute fails on; the trim that test reads; that the record carries the url as the attribute
/// holds it; the title chain and the site-url fallback as orders, on inputs that fail two levels at
/// once; that the subscription branch runs before the recursion, on the outline that is both; that
/// the category name is the parent's title read through the same chain; that miniflux attributes
/// are read against the resolved namespace, which a patch that accepted any namespace fails on, and
/// by the set of names, which a patch that added `proxyUrl` to the set fails on; the set
/// `ParseBool` accepts; the error naming the attribute it was reading; that a string name is not
/// read through the bool rule; and that the read walks every outline, not only the ones the branch
/// answers as a record. What these pins cannot fail on: the tokenizer's own rules, which its suites
/// pin, including the entity table and the tolerant reading of a malformed entity — the pins here
/// only show that the value reaches the record as read; the `head` fields, which the reference
/// reads but the parse result does not carry, so no pin can reach them; the error wording the
/// reference wraps around the parse failure, which is the handler's wording, not a rule; and the
/// `language` and `version` attributes the corpora carry, which the model has no field for and
/// which are not read.
@Suite struct OPMLReadTests {
    @Test func theRootNameIsTheOneTheModelTags() throws {
        // `Strict = false` does not relax the match: the root the model names is read, a root it
        // does not is the mismatch the reference reports.
        let documents = try OPMLParser.parse(Data(
            "<opml version=\"1.0\"><body><outline xmlUrl=\"http://e/f\"/></body></opml>".utf8))
        #expect(documents.count == 1, "the root the model names: \(documents)")

        do {
            _ = try OPMLParser.parse(Data("<rss><body></body></rss>".utf8))
            Issue.record("a root the model does not name must reach as the shape rule")
        } catch let error as OPMLError {
            #expect(error == .rootShape(rootLocal: "rss"), "\(error)")
        }
    }

    @Test func theReadFailureReachesAsTheReadsOwnFailure() throws {
        do {
            _ = try OPMLParser.parse(Data("garbage".utf8))
            Issue.record("a document the read cannot read must reach as a failure")
        } catch let error as OPMLError {
            #expect(error == .documentNotReadable(.unexpectedEOF), "\(error)")
        }
    }

    @Test func outlinesAreReadAtTheLevelTheModelFieldNames() throws {
        // The document field names `body>outline`, so an outline anywhere else is not read: the one
        // directly under the root is not, and the one inside `head` is not — `head` has no field
        // for outlines. The outline under `body` is read, and the recursion descends through the
        // children field, which matches direct children of the outline it reads.
        let document = Data("""
            <opml version="1.0">
            <outline xmlUrl="http://e/direct-under-root"/>
            <head><outline xmlUrl="http://e/in-head"/></head>
            <body>
            <outline text="cat"><outline text="kid" xmlUrl="http://e/read-through-the-children-field"/></outline>
            </body>
            </opml>
            """.utf8)
        let subscriptions = try OPMLParser.parse(document)
        #expect(subscriptions.map(\.feedURL) == ["http://e/read-through-the-children-field"],
            "\(subscriptions)")
        #expect(subscriptions.first?.categoryName == "cat", "the level the children field reads")

        // The control the patch has to keep: an outline that is a direct child of `body` is read.
        let direct = try OPMLParser.parse(Data(
            "<opml><body><outline xmlUrl=\"http://e/direct\"/></body></opml>".utf8))
        #expect(direct.map(\.feedURL) == ["http://e/direct"], "\(direct)")
    }

    @Test func theBranchIsTheUrlValueAlone() throws {
        // `type` is not in the model, so it cannot decide the branch: the `atom` outline with a url
        // is read as a record, and the `rss` outline without one is not.
        let subscriptions = try OPMLParser.parse(Data("""
            <opml version="1.0"><body>
            <outline type="atom" text="A" xmlUrl="http://e/a"/>
            <outline type="rss" text="B"><outline text="kid" xmlUrl="http://e/kid"/></outline>
            </body></opml>
            """.utf8))
        #expect(subscriptions.map(\.feedURL) == ["http://e/a", "http://e/kid"], "\(subscriptions)")
        #expect(subscriptions.map(\.categoryName) == ["", "B"], "\(subscriptions)")
    }

    @Test func theSubscriptionTestTrimsTheUrlValue() throws {
        // The test is `strings.TrimSpace(o.FeedURL) != ""`, so the whitespace value answers
        // nothing.
        let subscriptions = try OPMLParser.parse(Data("""
            <opml version="1.0"><body>
            <outline text="C" xmlUrl="   "/>
            </body></opml>
            """.utf8))
        #expect(subscriptions.isEmpty, "the whitespace value is not a subscription: \(subscriptions)")
    }

    @Test func theRecordCarriesTheUrlAsTheAttributeHoldsIt() throws {
        // The test trims, the record does not: the import stores what the record holds.
        let kept = try OPMLParser.parse(Data(
            "<opml><body><outline xmlUrl=\"http://e/spaced \"/></body></opml>".utf8))
        #expect(kept.first?.feedURL == "http://e/spaced ", "\(kept)")
    }

    @Test func theTitleChainIsTheOrderTheReferenceDefines() throws {
        // Each input fails two levels, so the value named is the level that runs first.
        #expect(OPMLReadRules.title(title: "T", text: "X", siteURL: "http://e/s",
            feedURL: "http://e/f") == "T", "title before text")
        #expect(OPMLReadRules.title(title: "", text: "X", siteURL: "http://e/s",
            feedURL: "http://e/f") == "X", "text before the site url")
        #expect(OPMLReadRules.title(title: "", text: "", siteURL: "http://e/s",
            feedURL: "http://e/f") == "http://e/s", "the site url before the feed url")
        #expect(OPMLReadRules.title(title: "", text: "", siteURL: "",
            feedURL: "http://e/f") == "http://e/f", "and the feed url last")
        #expect(OPMLReadRules.title(title: "", text: "", siteURL: "", feedURL: "") == "",
            "the empty chain answers empty")
    }

    @Test func theSiteURLFallsBackToTheFeedURL() {
        #expect(OPMLReadRules.siteURL(siteURL: "http://e/s", feedURL: "http://e/f") == "http://e/s",
            "the site url when it is there")
        #expect(OPMLReadRules.siteURL(siteURL: "", feedURL: "http://e/f") == "http://e/f",
            "and the feed url when it is not")
    }

    @Test func theSubscriptionBranchRunsBeforeTheRecursion() throws {
        // An outline that is both a subscription and a parent: the reference appends it and never
        // descends into its children, so the child url does not reach the list.
        let subscriptions = try OPMLParser.parse(Data("""
            <opml version="1.0"><body>
            <outline text="both" xmlUrl="http://e/parent"><outline text="kid" xmlUrl="http://e/kid"/></outline>
            </body></opml>
            """.utf8))
        #expect(subscriptions.map(\.feedURL) == ["http://e/parent"], "\(subscriptions)")

        // The control: without the url the same outline answers the recursion branch.
        let onlyParent = try OPMLParser.parse(Data("""
            <opml version="1.0"><body>
            <outline text="parent"><outline text="kid" xmlUrl="http://e/kid"/></outline>
            </body></opml>
            """.utf8))
        #expect(onlyParent.map(\.feedURL) == ["http://e/kid"], "\(onlyParent)")
    }

    @Test func theCategoryNameIsTheParentsTitleThroughTheSameChain() throws {
        // The category is `GetTitle` of the parent, so the chain that names a subscription title
        // names the category too. Each parent below carries one level of the chain, so a patch that
        // answered the raw `text` attribute would fail the input that carries only `title`.
        let document = Data("""
            <opml version="1.0"><body>
            <outline title="CatTitle"><outline text="kid" xmlUrl="http://e/1"/></outline>
            <outline text="CatText"><outline text="kid" xmlUrl="http://e/2"/></outline>
            <outline><outline text="kid" xmlUrl="http://e/3"/></outline>
            </body></opml>
            """.utf8)
        let subscriptions = try OPMLParser.parse(document)
        #expect(subscriptions.map(\.categoryName) == ["CatTitle", "CatText", ""], "\(subscriptions)")

        // The nesting half, read on its own: the child inherits the nearest parent title.
        let nested = try OPMLParser.parse(Data("""
            <opml version="1.0"><body>
            <outline text="Outer"><outline text="Inner"><outline text="kid" xmlUrl="http://e/5"/></outline></outline>
            </body></opml>
            """.utf8))
        #expect(nested.first?.categoryName == "Inner", "the nearest parent: \(nested)")
    }

    @Test func minifluxAttributesAreReadAgainstTheResolvedNamespace() throws {
        // A prefix the declarations do not resolve is not read. The declaration on the root is in
        // scope for every element below it, so the second document has no declaration at all: a
        // patch that accepted any namespace reads the value there and fails only this pin. The
        // value is one `ParseBool` accepts, so a patch that read the string names through the bool
        // rule answers the same here and cannot reach this pin.
        let resolved = try OPMLParser.parse(Data("""
            <opml xmlns:miniflux="https://miniflux.app/opml"><body>
            <outline xmlUrl="http://e/1" miniflux:userAgent="t"/>
            </body></opml>
            """.utf8))
        #expect(resolved.first?.userAgent == "t", "the name read through the resolved namespace")

        let unresolved = try OPMLParser.parse(Data("""
            <opml version="2.0"><body>
            <outline xmlUrl="http://e/2" miniflux:userAgent="prefix-not-resolved"/>
            </body></opml>
            """.utf8))
        #expect(unresolved.first?.userAgent == "", "the prefix the declarations do not resolve: \(unresolved)")
    }

    @Test func namesOutsideTheMinifluxSetAreNotRead() throws {
        // `proxyUrl` is a name the format carries and the switch set does not.
        #expect(OPMLReadRules.isMinifluxName("userAgent"), "a name in the set")
        #expect(!OPMLReadRules.isMinifluxName("proxyUrl"),
            "a name the format carries but the switch set does not")

        let onlyUnknown = try OPMLParser.parse(Data("""
            <opml xmlns:miniflux="https://miniflux.app/opml"><body>
            <outline xmlUrl="http://e/3" miniflux:proxyUrl="p"/>
            </body></opml>
            """.utf8))
        #expect(onlyUnknown.first?.userAgent == "", "a name outside the set answers nothing: \(onlyUnknown)")
    }

    @Test func theBoolValueIsTheSetParseBoolAccepts() throws {
        for accepted in ["1", "t", "T", "true", "TRUE", "True"] {
            #expect(try OPMLReadRules.boolValue(name: "crawler", value: accepted) == true,
                "accepted as true: \(accepted)")
        }
        for accepted in ["0", "f", "F", "false", "FALSE", "False"] {
            #expect(try OPMLReadRules.boolValue(name: "crawler", value: accepted) == false,
                "accepted as false: \(accepted)")
        }
    }

    @Test func theErrorNamesTheAttributeItWasReading() throws {
        // The reference reports the name of the attribute the rule was reading, so the pin reads a
        // name that is not the one the wording would answer if the name were hardcoded.
        do {
            _ = try OPMLParser.parse(Data("""
                <opml xmlns:miniflux="https://miniflux.app/opml"><body>
                <outline xmlUrl="http://e/1" miniflux:disabled="yes"/>
                </body></opml>
                """.utf8))
            Issue.record("a bool attribute outside the set must reach as the error")
        } catch let error as OPMLError {
            #expect(error == .invalidMinifluxAttribute(name: "disabled"), "\(error)")
        }
    }

    @Test func aStringNameIsNotReadThroughTheBoolRule() throws {
        // `ParseBool` runs only on the bool half of the set, so `userAgent="true"` is the string
        // and a value outside the bool set on a string name is read as the string, not as the
        // error.
        let read = try OPMLParser.parse(Data("""
            <opml xmlns:miniflux="https://miniflux.app/opml"><body>
            <outline xmlUrl="http://e/1" miniflux:userAgent="yes"/>
            </body></opml>
            """.utf8))
        #expect(read.first?.userAgent == "yes", "the string field takes the value as written: \(read)")
        #expect(read.first?.crawler == false, "the bool field keeps its own default: \(read)")
    }

    @Test func theReadWalksEveryOutlineNotOnlyTheRecords() throws {
        // `Decode` reads the miniflux attributes as it decodes every outline, so the bad attribute
        // on a category outline reaches as the error even though its child would have answered a
        // record.
        do {
            _ = try OPMLParser.parse(Data("""
                <opml xmlns:miniflux="https://miniflux.app/opml"><body>
                <outline text="cat" miniflux:crawler="yes"><outline text="kid" xmlUrl="http://e/4"/></outline>
                </body></opml>
                """.utf8))
            Issue.record("the outline that is not a subscription is read too")
        } catch let error as OPMLError {
            #expect(error == .invalidMinifluxAttribute(name: "crawler"), "\(error)")
        }
    }
}
