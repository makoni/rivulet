// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import Testing
@testable import RivuletCore

/// The hostile sanitizer corpus: inputs that try to make the sanitizer write active content, and
/// the URL rules the sanitizer reads attribute values through.
///
/// Every expected value is the reference's own output for its input, not this implementation's, so
/// a failure here is a difference in the port, and recording it in `docs/parity.md` is the only way
/// a difference can stay. The values were written by running Miniflux v2.3.3 at commit `c4d54f87`
/// through the reference's test helper options — `OpenLinksInNewTab: true`, base URL
/// `http://example.org/`, `TZ=UTC` — the method recorded in `docs/testing.md`.
///
/// Each rule line names the rule of the case under it, and every case here can fail on that rule: a
/// case is left out when a wrong implementation of the rule it names writes the same output, which
/// is what the fixture says. What the corpus cannot pin is content inside `math` or `svg`, which
/// the reference inserts through the foreign-content rules this port does not have. The limit of
/// 512 open elements is pinned by the two cases that mirror `TestDeeplyNestedpage`: the reference
/// reaches it by panicking and its own parse recovers that as an error, so a chain one past the
/// limit answers with nothing. No case reads a clock, the network or the machine's tzdata. The
/// `youtube` iframe case does read an embed value the reference answers from `config.Opts`: the
/// corpus uses the `SanitizerOptions` defaults, which are the values `config.NewConfigOptions()`
/// gives.
@Suite struct SanitizerHostileCorpusTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)
    private let baseURL = "http://example.org/"

    /// One case: the rule it pins, the input as the fixture writes it, the output the reference
    /// produced for it.
    struct Case {
        var rule: String
        var input: String
        var output: String
    }

    @Test func hostileInputWritesTheReferenceOutput() throws {
        let cases = try readCorpus()
        #expect(!cases.isEmpty, "the corpus fixture is empty")

        for c in cases {
            let sanitized = Sanitizer.sanitize(baseURL: baseURL, rawHTML: c.input, options: options)
            #expect(sanitized == c.output, "case: \(c.rule) input: \(c.input.debugDescription)")
        }
    }

    /// Reads the fixture: a `#` line names the rule of the case under it, and each case is an
    /// `input =` line followed by an `output =` line. Control bytes are the escape forms the
    /// fixture writes them as, and `(empty)` is an empty output.
    private func readCorpus() throws -> [Case] {
        var cases: [Case] = []
        var rule = ""
        var input = ""
        for line in try Fixtures.lines("sanitizer/hostile_corpus.txt") {
            if line.hasPrefix("#") {
                rule = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("input = ") {
                input = unescape(String(line.dropFirst(8)))
            } else if line.hasPrefix("output = ") {
                let written = String(line.dropFirst(9))
                let value = written == "(empty)" ? "" : unescape(written)
                cases.append(Case(rule: rule, input: input, output: value))
            }
        }
        return cases
    }

    /// The escape forms the fixture writes control bytes as: the three with a letter of their own,
    /// and `\x` with the two hex digits of the byte, which is what a control byte without a letter
    /// of its own has to be written as.
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
            case "r": out.append("\r")
            case "\\": out.append("\\")
            case "x":
                let digits = String(rest.prefix(2))
                guard let byte = UInt8(digits, radix: 16) else {
                    out.append("\\")
                    out.append(next)
                    continue
                }
                rest = rest.dropFirst(2)
                out.append(Character(UnicodeScalar(byte)))
            default:
                out.append("\\")
                out.append(next)
            }
        }
        return out
    }
}
