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
/// a failure here is a difference in the port, and recording it in `docs/parity.md` is the only
/// way a difference can stay. The values were written by running Miniflux v2.3.3 at commit
/// `c4d54f87` through the reference's test helper options — `OpenLinksInNewTab: true`, base URL
/// `http://example.org/`, `TZ=UTC` — the method recorded in `docs/testing.md`.
///
/// What the corpus cannot pin is stated in the fixture and here: content inside `math` or `svg`,
/// which the reference inserts through the foreign-content rules this port does not have, and the
/// 10000-depth guard, which belongs to the tokenizer and is pinned in
/// `Tests/RivuletCoreTests/HTMLTokenizerTests.swift`. A case whose read order is already the sorted
/// order cannot pin the formatting-element order rule, and the fixture names those cases.
///
/// No case reads a clock, a config, the network or the machine's tzdata. The reference reads
/// `config.Opts` for the iframe domains, and its default options are empty, which is the
/// `SanitizerOptions` default the corpus uses.
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
            #expect(sanitized == c.output, "case: \(c.rule)")
        }
    }

    /// Reads the fixture: a `#` line names the rule the cases under it pin, and each case is an
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
            case "x":
                // `\x0c` is the one escape form with more than the letter, because 0x0C has no
                // single-letter form of its own.
                rest.removeFirst(2)
                out.append(Character(UnicodeScalar(0x0C)))
            case "\\": out.append("\\")
            default:
                out.append("\\")
                out.append(next)
            }
        }
        return out
    }
}
