import Foundation
import Testing
@testable import RivuletCore

/// The typed error the parser reports for a document it cannot decide on, and the decision the
/// switch `ParseFeed` makes for the formats it can.
///
/// Every expected value is the reference's own output for its input, not this implementation's,
/// so a failure here is a difference in the port, and recording it in `docs/parity.md` is the
/// only way a difference can stay. The values were written by running Miniflux v2.3.3 at commit
/// `c4d54f87` (Go 1.26.0) through `DetectFeedFormat` and the switch `ParseFeed` makes, with
/// `TZ=UTC`, the method recorded in `docs/testing.md`. The reference reports the failure as its
/// sentinel `ErrFeedFormatNotDetected` (`internal/reader/parser/parser.go:17`), which the port
/// models as `ParserError.feedFormatNotDetected`.
///
/// The rules each case can fail on, checked by patching the rule and reverting: another case
/// for the typed error fails the pins that name it; the JSON rule read after the tokens fails
/// the case whose JSON content is followed by a real element; the first character read as
/// written, or one buffer read instead of reading until the first character, fails the case
/// whose whitespace is longer than the buffer; the count checked after the switch on the name
/// fails the case whose root is read as the 51st token; a version attribute matched only
/// without a prefix fails the prefixed case; and an angle bracket inside a quoted attribute
/// value tolerated fails the case that names the failure. The number the cap counts is pinned
/// only by the pair: a cap read as 49 fails the case read as the 50th token and a cap read as
/// 60 the case read as the 51st, so neither pins the number alone.
///
/// What a pin cannot fail on: the wording of a message, because the port models each failure as
/// one case; the size of the buffer, because a larger one writes the same decision for every
/// case; the characters above the basic plane Go's whitespace class counts, because no case
/// here has one; and which adapter is called, since the outcome compares the branch the switch
/// takes. Seven of the ten end states map to one case, so those pins fail only on the case the
/// mapping can tell apart, and the three cases that name no root share one answer and fail only
/// through it. Nothing here reads a clock, a locale or the network.
@Suite struct ParserErrorTests {
    /// One case: the rule it pins, the input as the fixture writes it, the decision the
    /// reference reported, the outcome of the switch, and the end state, which is not a
    /// decision.
    struct Case {
        var rule: String
        var input: String
        var decision: String
        var outcome: String
        var end: String
    }

    private let baseURL = "http://example.org/"
    private let now = ParsedDate(epochSeconds: 0, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    @Test func corpusCaseReportsTheReferenceDecision() throws {
        let cases = try readCorpus()
        #expect(!cases.isEmpty, "the corpus fixture is empty")

        for c in cases {
            let route = FeedParser.route(Data(c.input.utf8))
            #expect(name(of: route) == c.decision, "case: \(c.rule), the decision")

            // The switch, read as the reference reads it: a case it decides on is routed and
            // the rest is the typed error. For a routed case the reference's answer is only
            // that no failure was reported, because reading an adapter would compare the port's
            // output, not the reference's.
            if c.outcome == routedTo(c.decision) {
                var reportedFailure: ParserError?
                do {
                    _ = try FeedParser.parse(baseURL: baseURL, data: Data(c.input.utf8), now: now)
                } catch let failure as ParserError {
                    reportedFailure = failure
                } catch {
                    // A failure inside an adapter is not the switch's decision, so it is not
                    // this pin.
                }
                #expect(reportedFailure == nil, "case: \(c.rule), the reference routes this case")
            } else {
                #expect(throws: ParserError.feedFormatNotDetected) {
                    try FeedParser.parse(baseURL: baseURL, data: Data(c.input.utf8), now: now)
                }
            }

            // A scan that ends in a failure is read as the case the message names, so the end
            // state is recorded as data and mapped here rather than thrown out of the test.
            #expect(name(of: scanEnd(Data(c.input.utf8))) == expectedEnd(c.end),
                "case: \(c.rule), the end state")
        }
    }

    /// The outcome the switch reports for a decision, in the reference's words.
    private func routedTo(_ decision: String) -> String {
        "routed to the \(decision.split(separator: " ")[0]) adapter"
    }

    /// A decision as the reference writes it: the format, with the version when the format is
    /// Atom.
    private func name(of route: FeedFormatRoute) -> String {
        switch route {
        case .atom(let version): return version.isEmpty ? "atom" : "atom \(version)"
        case .rss: return "rss"
        case .rdf: return "rdf"
        case .json: return "json"
        case .none: return "unknown"
        }
    }

    /// The end state as the comparison reads it. A clean end is the documented equivalence
    /// recorded in `docs/parity.md`, and a failure is the case the reference's message names,
    /// which is all a pin can compare, because the port keeps one case for each failure.
    private func expectedEnd(_ recorded: String) -> String {
        if recorded.contains("unescaped <") { return "unescapedAngleInAttributeValue" }
        return "unexpectedEOF"
    }

    private func name(of failure: XMLError) -> String {
        switch failure {
        case .unescapedAngleInAttributeValue: return "unescapedAngleInAttributeValue"
        default: return "unexpectedEOF"
        }
    }

    /// The end the scan reaches, read the way the reference's scan reads it: the bytes are
    /// prepared first, which is what makes a declared label matter, and then read as tokens
    /// until the scan ends. A document that cannot be prepared cannot be tokenized either,
    /// which is the same end as a failure reached inside the scan, because the reference
    /// reports no failure to the caller on this path.
    private func scanEnd(_ data: Data) -> XMLError {
        let tokenizer: XMLTokenizer
        do {
            tokenizer = XMLTokenizer(try XMLReader.prepared(data))
        } catch let failure as XMLError {
            return failure
        } catch {
            return .charset(CharsetError.unsupportedLabel(""))
        }
        while true {
            do {
                if try tokenizer.nextToken() == nil { return .unexpectedEOF }
            } catch let failure as XMLError {
                return failure
            } catch {
                return .charset(CharsetError.unsupportedLabel(""))
            }
        }
    }

    /// Reads the fixture: a `#` line names the rule of the case under it, and each case is an
    /// `input =` line followed by the decision, the outcome and the end state the reference
    /// reported, in that order. The lines are read whole, keeping the blank ones, because a
    /// blank line is what tells the rule of a case from the notes written above the corpus.
    private func readCorpus() throws -> [Case] {
        var cases: [Case] = []
        var rule = ""
        var input = ""
        var decision = ""
        var outcome = ""
        var pendingRule = ""
        let fixture = String(decoding: try Fixtures.data("parser/parser_error_corpus.txt"),
            as: UTF8.self)
        for line in fixture.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) {
            if line.hasPrefix("# ") {
                pendingRule = (pendingRule.isEmpty ? "" : pendingRule + " ")
                    + String(line.dropFirst(2))
            } else if line.isEmpty {
                pendingRule = ""
            } else if line.hasPrefix("input = ") {
                rule = pendingRule
                pendingRule = ""
                input = unescape(String(line.dropFirst(8)))
            } else if line.hasPrefix("decision = ") {
                decision = String(line.dropFirst(11))
            } else if line.hasPrefix("outcome = ") {
                outcome = unescape(String(line.dropFirst(10)))
            } else if line.hasPrefix("end = ") {
                cases.append(Case(rule: rule, input: input, decision: decision, outcome: outcome,
                    end: unescape(String(line.dropFirst(6)))))
            }
        }
        return cases
    }

    /// The escape forms the fixture writes: the control bytes and the form a value needs to
    /// be written whole. Reading them is the rule the fixture was written with, so the
    /// comparison reads the fixture the way the reference wrote it.
    private func unescape(_ value: String) -> String {
        var out = ""
        var rest = Substring(value)
        while !rest.isEmpty {
            let char = rest.removeFirst()
            guard char == "\\", !rest.isEmpty else {
                out.append(char)
                continue
            }
            let next = rest.removeFirst()
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "\"": out.append("\"")
            case "x": out.append(scalar(rest.prefix(2))); rest = rest.dropFirst(2)
            default: out.append(char); out.append(next)
            }
        }
        return out
    }

    /// A single hexadecimal escape as the fixture writes it.
    private func scalar(_ hex: Substring) -> String {
        String(UnicodeScalar(UInt32(String(hex), radix: 16) ?? 0) ?? " ")
    }
}
