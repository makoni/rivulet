import Foundation
import Testing
@testable import RivuletCore

/// The `link` elements the minimal discovery scan reads, in the order the tokens arrive. Ported
/// from `internal/reader/subscription/finder.go` (`findSubscriptionsFromWebPage`) at `c4d54f87`,
/// cut to the one step the plan names for this port: the scan of the document. The reference's
/// other steps — the well-known paths, the canonical URL, the YouTube and GitHub handlers,
/// RSS-Bridge — are not ported, and the table row `minimal_scan` in `docs/parity.md` records what
/// is missing. The reference does not test the relation at all: it dispatches on the `type`
/// attribute alone, so the relation rule below is the port's own, and the same row records it.
///
/// What these pins can fail on, each checked by patching the rule and reverting (7 pins, 13
/// probes): the four type branches, which a patch that matched a fifth type fails; that the type
/// is compared as read, which a patch that folds case fails on the case that says so; that
/// `application/json` alone has the WordPress skip, which a patch that applied the skip to every
/// branch fails on the same path read through another type; that the selector asks for the `type`
/// attribute present, which a patch that read a link without it fails on; the relation rule as the
/// whole value, which a patch that compared the first token fails, and as the port's own, which a
/// patch that dropped it fails; that an empty href is skipped, which a patch that resolved the
/// empty value fails on; that the answers come in the order the tokens arrive, which a patch that
/// ordered them fails on; that the same resolved value is read once, which a patch that answered
/// both halves of a pair fails on; that the href is resolved against the document the scan was
/// given, which a patch that resolved against the root fails on; and that an href the parse cannot
/// read is skipped rather than passed through, which a patch that passed it fails on.
///
/// What they cannot fail on: the resolution rules themselves, which the URL layer pins; the
/// tokenizer's rules as rules of the tokenizer, which its own suite pins, including that a `link`
/// inside a raw-text element is text rather than an element and that the self-closing token kind is
/// an element — the scan reads through both; the charset steps no case here reads, which the
/// charset suite pins; that the attribute value is not trimmed, which the reference does not
/// either and which no case here can pin because the resolution layer decides what a space is; and
/// the reference's logging, which this port has no layer for.
@Suite struct SubscriptionDocumentLinksTests {
    @Test func theFourTypeBranchesAnswerInDocumentOrder() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="application/rss+xml" href="/a">
            <link rel="alternate" type="application/feed+json" href="/c">
            <link rel="alternate" type="application/atom+xml" href="/b">
            <link rel="alternate" type="application/json" href="/d">
            <link rel="alternate" type="application/opml" href="/e">
            <link rel="alternate" href="/f">
            </head></html>
            """.utf8)

        // A patch that matched a fifth type, or read a link with no type attribute at all, added
        // `e` or `f` here; and a patch that ordered the answers failed here, because `c` arrives
        // before `b`. The order is the order the tokens arrive, not the order the branches are
        // written in.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == [
                "https://example.org/a", "https://example.org/c", "https://example.org/b",
                "https://example.org/d",
            ], "the four branches, in document order")
    }

    @Test func theTypeIsComparedAsItIsGiven() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="Application/RSS+xml" href="/folded">
            <link rel="alternate" type="application/rss+xml" href="/as-given">
            </head></html>
            """.utf8)

        // The reference's switch is on the value as the attribute holds it, so a patch that folded
        // the case answered both here.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/as-given"],
            "the branch that is not folded")
    }

    @Test func theWordPressPathIsSkippedByTheJSONBranchAlone() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="application/json" href="/wp-json/feed">
            <link rel="alternate" type="application/rss+xml" href="/wp-json/feed">
            </head></html>
            """.utf8)

        // The same path read through the other branch answers, so a patch that applied the skip to
        // every branch cannot pass this pin.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/wp-json/feed"],
            "the skip is part of the branch, not of the scan")

        // The value is compared as the attribute holds it, and the scan reads the href, not the
        // document URL, for this test.
        let upper = Data("""
            <html><head><link rel="alternate" type="application/json" href="/WP-JSON/feed"></head></html>
            """.utf8)
        #expect(SubscriptionDocumentLinks.feedURLs(document: upper, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/WP-JSON/feed"],
            "the path is read as it is given")
    }

    @Test func theRelationRuleIsThePortsOwnAndReadsTheWholeValue() {
        let document = Data("""
            <html><head>
            <link type="application/rss+xml" href="/no-relation">
            <link rel="alternate feed" type="application/rss+xml" href="/two-tokens">
            <link rel="ALTERNATE" type="application/rss+xml" href="/folded">
            <link rel="alternate" type="application/rss+xml" href="/read">
            </head></html>
            """.utf8)
        // The reference reads the first two as well, because it does not test the relation at all;
        // this port's scan is the plan's minimal rule, so the relation is the whole value. A patch
        // that compared the first token of the value, or that compared it case-sensitively, fails
        // on the second and the third case.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/folded",
            "https://example.org/read"], "the port's own rule, read whole")
    }

    @Test func anEmptyHrefIsSkippedAndTheFirstValueTheScanFoundAnswers() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="application/rss+xml">
            <link rel="alternate" type="application/rss+xml" href="">
            <link rel="alternate" type="application/rss+xml" href="/first">
            <link rel="alternate" type="application/rss+xml" href="/second">
            </head></html>
            """.utf8)
        // A patch that resolved the empty value added the document URL itself. The scan answers the
        // whole list it read; which value the handler picks from it is the socket suite's pin, and
        // the order is the pin above.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/first",
            "https://example.org/second"], "the empty value is skipped, the two others are read")

        let pick = Data("""
            <html><head>
            <link rel="alternate" type="application/rss+xml" href="/first">
            <link rel="alternate" type="application/atom+xml" href="/second">
            </head></html>
            """.utf8)
        #expect(SubscriptionDocumentLinks.feedURLs(document: pick, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/first",
            "https://example.org/second"], "the scan answers the list in the order it read it")
    }

    @Test func theSameResolvedValueIsReadOnce() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="application/rss+xml" href="/a">
            <link rel="alternate" type="application/atom+xml" href="/a">
            <link rel="alternate" type="application/json" href="https://example.org/a">
            <link rel="alternate" type="application/atom+xml" href="/b">
            </head></html>
            """.utf8)
        // The dedupe is on the resolved value, so the three spellings of the same value answer
        // once, whatever the format each of them names — a patch that keyed on the raw attribute,
        // or that keyed on the pair of attribute and format, answered four here.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org") == ["https://example.org/a",
            "https://example.org/b"], "the set is keyed by the resolved value")
    }

    @Test func theScanResolvesAgainstTheDocumentItWasGivenAndSkipsWhatItCannotRead() {
        let document = Data("""
            <html><head>
            <link rel="alternate" type="application/rss+xml" href="sub/a">
            <link rel="alternate" type="application/rss+xml" href="/root/b">
            <link rel="alternate" type="application/rss+xml" href="https://other.example.org/c">
            <link rel="alternate" type="application/rss+xml" href="/a%zz">
            </head></html>
            """.utf8)
        // The reference resolves against the `<base href>` value when the document has one, and
        // otherwise against the URL it was given — the deviation the same table row records. Here
        // the scan is given one base, so a patch that resolved against the root moved `sub/a` to
        // the root, and a patch that passed the value the parse cannot read through added the last
        // case. The base is given with the trailing slash because the resolution rule drops a base
        // path that is not a
        // directory, which the URL layer pins on its own.
        #expect(SubscriptionDocumentLinks.feedURLs(document: document, contentType: "text/html",
            documentURL: "https://example.org/blog/") == [
                "https://example.org/blog/sub/a", "https://example.org/root/b",
                "https://other.example.org/c",
            ], "the base the scan was given, and the href the parse cannot read is skipped")
    }
}
