# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** implementation in progress: the charset slice is merged (labels, detection and
transcoding, fixture corpus) and so is the XML reader slice (tokenizer, lexical scanner, entity
table, format detection); the date parser slice is merged too (Go's `parse` over the reference's
209 layouts, with a fixed zone table in place of the machine's tzdata); the URL layer the sanitizer
resolves through is merged too (the `net/url` subset, the URI-scheme allowlist, the
tracking-parameter cleaner). The sanitizer itself and then the format adapters are next.

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
- [x] Charset detection and transcoding: WHATWG label table transcribed from
      `golang.org/x/text` v0.40.0 (BSD-3-Clause, attributed in `NOTICE`); both reference paths
      (`CharsetReader`, `NewCharsetReaderFromBytes`) with BOM → content-type → meta prescan
      (1024 bytes) → UTF-8 heuristic → `windows-1252` default; output is always UTF-8.
      Platform decoder gaps (EUC-JP on Linux) go through a glibc `iconv` fallback; the
      deviations are in `docs/parity.md`.
- [ ] XML quirks: BOM/leading garbage, invalid entities, CDATA; decision table from the corpus.
- [ ] Sanitizer (SwiftSoup): allowlist of tags/attributes ported from
      `internal/reader/sanitizer` (media: `img/video/audio/source`, `iframe` with a domain
      allowlist); strips scripts, styles, event handlers, `javascript:` URLs; deterministic output.
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
- Sanitizer: ported rules + a hostile corpus (script tags, `onerror`, `javascript:` URLs,
  nested obfuscation).

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
