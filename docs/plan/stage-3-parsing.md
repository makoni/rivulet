# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** implementation in progress: the charset slice is merged (labels, detection and
transcoding, fixture corpus) and so is the XML reader slice (tokenizer, lexical scanner, entity
table, format detection); the date parser slice is merged too (Go's `parse` over the reference's 209
layouts, with a fixed zone table in place of the machine's tzdata); the URL layer the sanitizer
resolves through is merged too (the `net/url` subset, the URI-scheme allowlist, the
tracking-parameter cleaner). The sanitizer slice is merged (PR #13), with the findings from its
review landed as PR #14, and its text layer — `StripTags` and `TruncateHTML` — as PR #15. The
normalized model with the shared primitives and the RSS adapter is merged as PR #16, and RDF
(RSS 1.0) as PR #17, and Atom 1.0 and 0.3 as PR #18. The format adapters are landing one format at a
time: the JSON reader — our own reader over the bytes, because Miniflux reads a JSON feed through
`encoding/json` — is merged as PR #19, and the JSON Feed adapter is next.

## Scope

- [ ] Parser layer, written by us — no external feed library, decided in the
      [stage 3 spike](spike-3-parser.md): RSS 2.0 (+ 0.91/0.92 to be tested), RDF (RSS 1.0/0.90),
      Atom 1.0 and 0.3, JSON Feed; a tree reader fills `ParsedFeed` and `ParsedEntry` directly.
      Atom 0.3 `issued`/`modified` and the version attribute are in scope, which an external model
      layer could not express.
- [ ] Entry identity fallback chains and SHA-256 hashing, exactly as the reference does
      (per-format rules in `docs/reference-notes.md`).
- [x] Date parsing: port the reference rules — integer Unix timestamp first, RFC822/850/1123
      interpreted as local time, 209 layouts after normalization (3 in the local-time group and 206
      in the list), PST/PDT workaround, UTC-offset clamping; adapters fall back to "now" when
      parsing fails completely. Zone abbreviations read through a fixed table instead of the
      machine's tzdata — see `docs/parity.md`.
- [x] Charset detection and transcoding: WHATWG label table transcribed from the
      `golang.org/x/text` `encoding/htmlindex` copy in the module cache, which `miniflux/go.mod`
      pins at v0.40.0 (BSD-3-Clause, attributed in `NOTICE`); both reference paths (`CharsetReader`,
      `NewCharsetReaderFromBytes`) with BOM → content-type → meta prescan (1024 bytes) → UTF-8
      heuristic → `windows-1252` default; output is always UTF-8. Platform decoder gaps (EUC-JP on
      Linux) go through a glibc `iconv` fallback; the deviations are in `docs/parity.md`.
- [ ] XML quirks: BOM/leading garbage, invalid entities, CDATA; decision table from the corpus.
- [ ] Sanitizer: allowlist of tags/attributes ported from `internal/reader/sanitizer` (media:
      `img/video/audio/source`, `iframe` with a domain allowlist); strips scripts, styles, event
      handlers, `javascript:` URLs; deterministic output. It reads through our own HTML tokenizer
      subset and fragment tree rather than through SwiftSoup — the decision and the reason are in
      `docs/parity.md`, and SwiftSoup stays the dependency `EntryText` uses. The core is merged, and so
      is the text layer it reads through (`StripTags` and `TruncateHTML`, which the format adapters
      call); the format adapters are next.
- [x] Normalization, URL part: relative URL resolution against the feed/site URL, ported from
      `internal/urllib` and the `net/url` subset it reads through (parse order, raw path, host
      class, `ResolveReference`), with the URI-scheme allowlist and the tracking-parameter cleaner.
      Entity decoding and whitespace normalization are still open.
- [ ] Feed metadata: title, site URL, description, icon link; typed errors ("not a feed",
      "feed not found", too large).
- [x] Fixtures ported to `Tests/RivuletCoreTests/Fixtures/<area>/` with a provenance `README.md`
      (upstream commit, license, copied vs regenerated); `NOTICE` updated when they land.

## Implementation notes

- The spike is done (2026-10-23) and the decision is to write the layer ourselves: no external feed
  library. The cases that decide what our reader must tolerate are recorded in
  [stage 3 spike](spike-3-parser.md): charset label versus bytes, no detection without a label,
  strictness, date semantics and Atom 0.3.
- The reader slice landed (2026-10-24): the lexical primitives, the byte-level tokenizer with the
  reference's tolerance, the HTML entity table, the `XMLElement` tree and format detection. The
  tolerance rules are recorded in `docs/reference-notes.md` and the deviations in `docs/parity.md`.
  The format adapters read through it.
- The URL layer slice landed (2026-10-25) as #12: the `net/url` subset the reader resolves through,
  the URL rules from `internal/urllib`, the URI-scheme allowlist and the tracking-parameter cleaner.
  It came before the sanitizer, because the sanitizer resolves the attributes it keeps through it,
  and before the adapters, because they call the cleaner and the sanitizer. The subset boundary and
  the pins that are traced rather than ported from a corpus are recorded in `docs/parity.md`.
- The sanitizer slice reads through the port's own tokenizer subset and fragment tree rather than
  through SwiftSoup, and it builds the output string itself, which is what the reference does. The
  rules that decide which tags and attributes survive are the allowlists in
  `Sources/RivuletCore/Reader/Sanitizer/`; the rules that decide the tree the renderer walks are the
  insertion modes, and the subset of them that is ported is recorded in `docs/parity.md`.
- Sanitizer output must be deterministic — golden-file friendly.
- The sanitizer is security-critical (see `AGENTS.md`): relax nothing to make tests pass.

## Tests

### Unit (fixture/golden, ported from Miniflux)

- Encoding: every fixture assertion the reference makes is reproduced; the 11 fixture files in
  `Fixtures/encoding/` cover prolog labels, wrong labels over valid UTF-8, KOI8-R feeds, the
  content-type path and the 1024-byte detection window.
- Parser: 8 fixtures → normalized feed/entry golden outputs.
- XML: 3 fixtures.
- Dates: ported table-driven cases. The "now" fallback belongs to the format adapters, so it is
  covered with them rather than by the date slice.
- URL: the ported tables from `internal/urllib/url_test.go` and
  `internal/reader/urlcleaner/urlcleaner_test.go`, plus the pins traced against Go's `net/url`
  source. There is no fixture corpus here, because the reference has none for this area.
- Sanitizer: ported rules + a hostile corpus (script tags, `onerror`, `javascript:` URLs, nested
  obfuscation). The reference corpus is ported in full except the fuzz target `FuzzSanitizer`, whose
  expectation is that the output has no more tokens than the input, which needs a fuzz harness and a
  seed corpus that Swift Testing does not have. The text layer (`StripTags` and `TruncateHTML`) is
  the suite this PR adds. The tokenizer and insertion-mode rules have no reference corpus, so they
  are pinned through the sanitizer output as traced against `golang.org/x/net/html` — see
  `docs/parity.md` — except the four the output cannot show, a tag name and an attribute key
  carrying a NUL, the shape of the entity table, and where comment data ends, which are asserted
  through the tokenizer itself.

### Integration

- Stub server → fetch → parse → sanitize → store: entries appear exactly once with sanitized
  content.
- Re-fetch with `304` changes nothing; a malformed feed yields a typed error and leaves feed
  state intact.

## Exit criteria

- [ ] The ported Miniflux fixture corpus is green.
- [ ] Hostile sanitizer corpus produces no active content.

## Risks

- The tolerance decision table for the parser (BOM, garbage before the prolog, invalid entities,
  CDATA) is the biggest project risk, because the reference is lenient and a strict XML reader is
  not; the spike measured this on the corpus. Deviations are recorded in `docs/parity.md` as soon as
  observed — stage 7 consolidates tolerances.

## Backlog

Findings from the JSON reader review (#19) that do not change behavior:
- `JSONReader.read`'s guard for an empty token list is unreachable, because the machine reports
  the end of input before assembly, which is what the pins for an empty document assert.
- `value()`'s branch for the structural tokens mirrors `phasePanicMsg` and cannot be reached
  through a stream the machine validated, so no assertion can fail on it.
- `unquoteBytes` also has a `'` branch, and Go's `unquote` writes letters `stateInStringEsc`
  does not accept, so the set this machine reads is smaller than the reference's and the extra
  branch cannot be pinned here.
- `JSONScanner.swift` is at 367 lines, above the 150–300 aim: the literal writing is split out
  as `JSONUnquote`, so the machine itself is the part that stays long.

Findings from the URL layer review (#12) that do not change behavior:

- `String()` keeps two Go branches this subset does not port: the first path slash is escaped when
  `OmitHost` is set and the path begins with the authority marker, and the `./` prefix is written
  for a first path segment that carries a colon when nothing else was written. Neither is reachable
  through `parse` or `resolvePath`, so no assertion can fail on them here; they belong to the subset
  boundary recorded in `docs/parity.md`.
- The `*` path row in `docs/parity.md` describes a branch this subset does not port, but a `*` read
  through `parse` still round-trips as `*` through the recorded raw form, so the row should say what
  is observable instead of what the unported branch would do.
- A bracketed host is read through its own mode in Go, and the bracketed name is checked as an
  address. Both stay outside the subset the reader resolves through; the zone mode rules of
  `unescape` are the part that would change a value.
- `TestIsValidProxyURL` and `TestJoinBaseURLAndPath` are not ported, because no reader path uses
  them. They land with the fetcher's proxy check and the stage 6 integrations, through the same
  parse.

Findings from the RSS adapter review (#16) that do not change behavior:

- `SortedNames` reads the duplicate check on the bytes, but the case that separates the two readings
  uses two spellings that are not canonically equivalent, so it pins the order only. The pair that
  would pin the duplicate half is `caf\u{00E9}` against `cafe\u{0301}`: the reference inserts both,
  because the bytes differ.
- No upstream case shows how `Inner` treats a comment inside the element, so that boundary of the
  reconstruction is recorded in `docs/parity.md` without a pin.
- `docs/testing.md` reads as if the seven sanitizer suites all name traced pins, while the two
  text-layer suites port the upstream corpus.
- `HTMLFragmentTree.swift` is at 465 lines, close to the hard cap.
- `docs/plan/stage-6-cli.md:11` is 102 columns, which predates this stage.

Findings from the sanitizer slice review that do not change behavior:

- `TestInvalidURLScheme` copies the upstream case, where the invalid scheme sits on an `<a>` that
  has no `href`; the element is unwrapped because `href` is mandatory, so the case does not pin the
  scheme. Add an `<a href="file:///etc/passwd">` case; scheme rejection is pinned for `img` and
  `srcset` today.
- `mediaValidatorsDoNotApplyToOtherTags` names `fetchpriority` and `decoding`, but a `p` allowlist
  is empty, so the pair would pass even if the validators did not exist. The validators are pinned
  by the `img` table; the comment should say the pair only pins the tag gate.
- `startTagInRowMode` looks for an open `tr` anywhere in the stack, where the reference uses
  `popUntil(tableRowScope, tr)`. Equivalent while the stack is well formed; a scope-aware version
  belongs with the nested-table work.
- `SanitizerIFrameTests` keeps upstream's `contains("<iframe")` assertion, which would pass for a
  wrong iframe output; the exact-output cases next to it cover the same domains.
- `HTMLEscape.escapeString` walks `Character`s, so a decoded `&#13;&#10;` arrives as one CRLF
  grapheme and the CR is not escaped; the reference writes `&#13;\n`. A lone CR is escaped and
  pinned. Walk unicode scalars if a feed can produce the pair.

Findings from the RDF adapter review (#17) that do not change behavior:

- The last-match rule is pinned in `RDFEntryTests`, which is the RDF copy of the helper. Reverting the
  RSS copy to the first match leaves the suite green, so an RSS case with two same-level `title`
  elements is what would pin the rule for that format too.
- `XMLReaderTests.swift` is at 500 lines, which is the cap rather than the aim, so the next case added
  to it needs its own suite.

Findings from the Atom adapter review (#18) that do not change behavior:
- `Atom10Adapter.entry` is 63 lines, above the aim, because the entry chain reads the link, the
  content, the title, the author, the date and the attachments in one pass. The media and the date
  parts are already helpers, so the rest splits by group.
- `AtomTextConstructTests` paraphrases the upstream CDATA inputs with characters already decoded,
  so those rows cannot fail on the point their comment names — that the reader does not resolve
  inside a CDATA section. `theTwoEntryPointsDoNotAgreeOnCDATA` is the pair that pins the two entry
  points, so the rows should carry `&#8220;` and `&lt;tag&gt;` as the upstream corpus writes them.
- `RSSAdapter.parse` is 51 lines, above the aim, so the enclosure and the identity halves need
  named helpers.
- Prose that predates this stage and is over the width: `docs/testing.md` 157-166, and this file
  at 39, 169 and 172.
