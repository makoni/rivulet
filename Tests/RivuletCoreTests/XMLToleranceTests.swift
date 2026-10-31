import Foundation
import Testing
@testable import RivuletCore

/// The tolerance corpus: the inputs the decision table in `docs/reference-notes.md` rests on,
/// read through the reference's reader path.
///
/// Every expected value is the reference's own output for its input, not this implementation's,
/// so a failure here is a difference in the port, and recording it in `docs/parity.md` is the
/// only way a difference can stay. The values were written by running Miniflux v2.3.3 at commit
/// `c4d54f87` (Go 1.26.0) through `NewXMLDecoder` and `Token()` — the reader path, not `Decode`
/// — with `TZ=UTC`, the method recorded in `docs/testing.md`.
///
/// The comparison reads the stream as the reference reports it, so it cannot show the production
/// a run of text came from: `Token()` reports a CDATA run as character data like any other run,
/// and the flag this port keeps for it is pinned in `XMLTreeTests`. It cannot show the wording of
/// a failure either: the reference gives a message and the port models each failure as one case,
/// so the test compares the case the message names, and a wrong implementation reports another
/// case. A message the mapping has not read fails on the mapping itself, so a case with a new
/// message cannot pass on a fallback. The end of the stream is the same modeling choice recorded
/// in `docs/parity.md`: the reference reports `io.EOF` at a clean end, where this port reports
/// `unexpectedEOF` for a clean end and for an end reached inside an element alike. Nothing here
/// reads a clock, a locale or the network.
@Suite struct XMLToleranceTests {
    /// One case: the rule it pins, the input as the fixture writes it, the stream the reference
    /// reported, and its end state, which is not a token so it is kept apart from the parts.
    struct Case {
        var rule: String
        var input: String
        var parts: [String]
        var end: String
    }

    @Test func corpusCaseWritesTheReferenceStream() throws {
        let cases = try readCorpus()
        #expect(!cases.isEmpty, "the corpus fixture is empty")

        for c in cases {
            let (parts, end) = try stream(c.input)
            #expect(parts == c.parts, "case: \(c.rule), input: \(c.input.debugDescription)")
            let mapped = try #require(expectedEnd(c.end),
                "case: \(c.rule), end message \(c.end.debugDescription) is not mapped")
            #expect(end == mapped, "case: \(c.rule), end state")
        }
    }

    /// The stream this port reports for an input, read the way the reference reads it: the bytes
    /// are prepared first, which is what makes a declared label matter, and then read as tokens.
    /// The parts are written in the shape the fixture writes them, so the comparison is the stream
    /// as such.
    private func stream(_ input: String) throws -> ([String], String) {
        var parts: [String] = []
        let tokenizer = XMLTokenizer(try XMLReader.prepared(Data(input.utf8)))
        while true {
            let token: XMLToken?
            do {
                token = try tokenizer.nextToken()
            } catch let failure as XMLError {
                return (parts, name(of: failure))
            } catch {
                return (parts, "other")
            }
            guard let token else { return (parts, "EOF") }
            switch token {
            case .startElement(let name, _): parts.append("start \(key(name))")
            case .endElement(let name): parts.append("end \(key(name))")
            case .characterData(let value, _): parts.append("chardata \"\(escaped(value))\"")
            case .processingInstruction(let target, let content):
                parts.append("procinst \"\(escaped(target))\" \"\(escaped(content))\"")
            case .comment(let content): parts.append("comment \"\(escaped(content))\"")
            case .directive(let content): parts.append("directive \"\(escaped(content))\"")
            }
        }
    }

    /// A name as the reference writes it: the space and the local name, with an empty space
    /// written as nothing before the colon.
    private func key(_ name: XMLName) -> String { "\(name.namespace):\(name.local)" }

    /// The end state as the comparison reads it. A clean end is the documented equivalence
    /// recorded in `docs/parity.md`, and a failure is the case the reference's message names,
    /// which is all a pin can compare, because the port keeps one case for each failure. A
    /// message the mapping does not name answers nil, so a case with a message this mapping has
    /// not read fails on the mapping rather than passing on a fallback to the clean-end case.
    private func expectedEnd(_ recorded: String) -> String? {
        if recorded == "EOF" { return "unexpectedEOF" }
        if recorded.contains("unexpected end element") { return "unexpectedEndElement" }
        if recorded.contains("illegal character code") { return "illegalCharacterCode" }
        if recorded.contains("unescaped ]]") { return "unescapedBracketInText" }
        if recorded.contains("invalid <![") { return "malformedCDATA" }
        return nil
    }

    private func name(of failure: XMLError) -> String {
        switch failure {
        case .unexpectedEOF: return "unexpectedEOF"
        case .invalidXMLName: return "invalidXMLName"
        case .unexpectedEndElement: return "unexpectedEndElement"
        case .invalidEndTag: return "invalidEndTag"
        case .elementNameExpected: return "elementNameExpected"
        case .attributeNameExpected: return "attributeNameExpected"
        case .processingInstructionTargetExpected: return "processingInstructionTargetExpected"
        case .unsupportedXMLVersion: return "unsupportedXMLVersion"
        case .malformedComment: return "malformedComment"
        case .malformedCDATA: return "malformedCDATA"
        case .unescapedBracketInText: return "unescapedBracketInText"
        case .unescapedAngleInAttributeValue: return "unescapedAngleInAttributeValue"
        case .selfClosingTagNotClosed: return "selfClosingTagNotClosed"
        case .endTagNamespaceMismatch: return "endTagNamespaceMismatch"
        case .illegalCharacterCode: return "illegalCharacterCode"
        case .charset: return "charset"
        }
    }

    /// Reads the fixture: a `#` line names the rule of the case under it, and each case is an
    /// `input =` line followed by a `stream =` line, whose last part is the end state.
    private func readCorpus() throws -> [Case] {
        var cases: [Case] = []
        var rule = ""
        var input = ""
        for line in try Fixtures.lines("xml/tolerance_corpus.txt") {
            if line.hasPrefix("# ") {
                rule = (rule.isEmpty ? "" : rule + " ") + String(line.dropFirst(2))
            } else if line.hasPrefix("input = ") {
                input = unescape(String(line.dropFirst(8)))
            } else if line.hasPrefix("stream = ") {
                let parts = String(line.dropFirst(9)).split(separator: " | ").map(String.init)
                let end = parts.last ?? "EOF"
                let streamParts = parts.isEmpty ? [] : Array(parts[0..<parts.count - 1])
                cases.append(Case(rule: rule, input: input, parts: streamParts, end: end))
            }
        }
        return cases
    }

    /// The escape forms the fixture writes: the byte-order mark, the characters above the basic
    /// plane, the control bytes, and the two forms a value needs to be written whole. Reading and
    /// writing them is the same rule, so the comparison reads the fixture and writes the port's
    /// stream the same way.
    private func escaped(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x0A: out.append("\\n")
            case 0x09: out.append("\\t")
            case 0x22: out.append("\\\"")
            case 0xFEFF: out.append("\\ufeff")
            case let c where c < 0x20 || c == 0x7F: out.append("\\x" + hex(c, 2))
            case let c where c > 0xFFFF: out.append("\\U" + hex(c, 8))
            default: out.append(String(scalar))
            }
        }
        return out
    }

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
            case "u": out.append(scalar(rest.prefix(4))); rest = rest.dropFirst(4)
            case "U": out.append(scalar(rest.prefix(8))); rest = rest.dropFirst(8)
            default: out.append(char); out.append(next)
            }
        }
        return out
    }

    private func scalar(_ hex: Substring) -> String {
        String(UnicodeScalar(UInt32(String(hex), radix: 16) ?? 0) ?? " ")
    }

    private func hex(_ value: UInt32, _ digits: Int) -> String {
        String(format: "%0*x", digits, value)
    }
}
