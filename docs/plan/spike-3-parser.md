# Stage 3 spike — external feed library against the reference corpus

**Run:** 2026-10-23. **Question:** does an external Swift feed library replace the parser layer the
plan would otherwise write?

## Method

FeedKit (`nmdias/FeedKit`, MIT) was built as a scratch package, never as a project dependency, and
run over the reference fixture corpus: encoding 11 files, parser 8, XML 3. Two passes per fixture:
the bytes as they arrive from the network, and the same bytes after our own transcode, which is what
stage 3's encoding layer would hand to a parser. A third pass feeds it documents that our own XML
layer would produce (label stripped, entities normalized, garbage before the prolog removed, date
rewritten to a canonical form).

Expected values are the reference's own: the strings its tests assert (`Café`, `Anaïs`/`Jürgen`,
`Пример RSS ленты`, `Anas`/`Jrgen`) and the rules in `internal/reader/encoding/encoding.go` and
`internal/reader/xml/decoder.go`. The harness itself is scratch and is not committed.

## Results

| Case | Reference | FeedKit |
| --- | --- | --- |
| Non-UTF-8 bytes with a correct label (`koi8r.xml`, `windows-1252.xml`) | transcode by the label | same, decodes correctly |
| Bytes already valid UTF-8, label wrong (`utf8-incorrect-prolog.xml`) | label ignored, bytes pass through → `테스트 피드` | label wins → mojibake |
| No label, non-UTF-8 bytes (`no_encoding_ISO-8859-1.xml`) | label from BOM → meta prescan → default | no detection layer, decode error |
| Unusable label (`invalid-prolog.xml`) | bytes pass through, document decodes | parse error |
| Non-feed root (`xml/testdata/iso88591.xml`, `<note>`) | decoded as an XML document | format detection fails, cannot decode at all |
| Invalid entity, junk before the prolog | tolerated (`Strict = false`, `decoder.Entity = xml.HTMLEntity`) | parse error |
| Integer Unix date (`1173998729`) | `strconv.ParseInt` first → `time.Unix` | decode error |
| Unreadable date (`not a date`) | entry date falls back to `time.Now()` | the whole document fails: the model throws, there is no seam |
| ~20 date patterns vs the reference's ~70 | UTC, plus `PST/PDT/EST/EDT` named-zone workaround and offset clamping | UTC only, no named-zone handling, no clamping |
| Atom 0.3 `issued`/`modified` | mapped to the entry date, which feeds hash and dedup | no model field → date is nil |
| RSS 0.91, RSS 0.92, RDF, JSON Feed 1.1, CDATA, `content:encoded` | — | detected and decoded, agreement |

One observation worth keeping: for the same bytes, FeedKit produced the reference string in one run
and the label-decoded mojibake in another. A charset path whose behaviour depends on the document
label we do not control is not something parity can be built on.

## What the library does not cover

Everything that makes the reference behavior observable sits outside it: charset detection and
transcoding, date parsing, XML tolerance, entry identity and hashing, sanitizing. The library is a
model layer plus an XML decoder. With our own preprocessing it parses the corpus correctly, which
means the preprocessing — that is stage 3 itself — is what carries the parity, and what stays broken
are the parts baked into its models: date semantics, Atom 0.3, non-feed documents.

Its model layer is 15,237 lines of Swift across 122 files with 14 namespaces. The reference reads
only Dublin Core, Media and iTunes into `model.Feed`/`model.Entry`. Our target is one normalized
model, so the per-format structs — which Go needs because it decodes through struct tags — are not
on our path.

## Decision

No new dependency. The parser layer is ours: an XML tree reader over Foundation's `XMLParser`, a
charset layer (WHATWG label → `String.Encoding`, BOM, prescan, default), the date parser with the
reference rules, adapters filling `ParsedFeed`/`ParsedEntry` directly from the tree, SwiftSoup for
the sanitizer, and the identity/hashing rules. Estimated size: 1,200–1,600 Swift lines, against the
reference's 4,045 Go lines for the same areas, and no addition to the dependency graph — which is
what `AGENTS.md` asks for, including the rule that a new dependency needs explicit approval.

Revisit only if a later stage needs raw namespace data as part of the API (podcast, iTunes, georss);
the plan does not ask for it. Nothing here is recorded in `docs/parity.md`: no Rivulet behavior is
affected, these are measurements of a library we decided not to use.

## Follow-ups for stage 3

- - Ported in stage 3: the reference's tests for these files assert only the decoded strings, so
  the golden outputs for the parser fixtures are defined by us and recorded as golden files in
  `Tests/RivuletCoreTests/Fixtures/parser/golden/`.
- The 8 parser fixtures are used by the reference only in benchmarks and fuzz seeds; no golden
  values exist upstream for them.
- The date rule in `docs/reference-notes.md` said "local time"; the reference parses these layouts
  in UTC with a named-zone exception (`PST/PDT` → Los Angeles, `EST/EDT` → New York). Corrected
  there.
