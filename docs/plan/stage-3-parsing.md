# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** spike complete (2026-10-23), implementation not started. **Effort:** XL (the hardest
stage). **Depends on:** Stage 2.

## Scope

- [ ] Parser layer, written by us — no external feed library, decided in the
      [stage 3 spike](spike-3-parser.md): RSS 2.0 (+ 0.91/0.92 to be tested), RDF (RSS 1.0/0.90),
      Atom 1.0 and 0.3, JSON Feed; a tree reader fills `ParsedFeed` and `ParsedEntry` directly.
      Atom 0.3 `issued`/`modified` and the version attribute are in scope, which an external model
      layer could not express.
- [ ] Entry identity fallback chains and SHA-256 hashing, exactly as the reference does
      (per-format rules in `docs/reference-notes.md`).
- [ ] Date parsing: port the reference rules — integer Unix timestamp first, RFC822/850/1123
      interpreted as local time, ~70 layouts after normalization, PST/PDT workaround, UTC-offset
      clamping; adapters fall back to "now" when parsing fails completely.
- [ ] Charset detection and transcoding: WHATWG label → `String.Encoding` map (BOM → meta prescan
      → default). Foundation on Linux was **verified** to decode `windows-1251`, `windows-1252`,
      ISO-8859-1, ISO-8859-15, KOI8-R, GB18030, Big5; some encodings need raw encoding values
      (no named constants). Output is always UTF-8.
- [ ] XML quirks: BOM/leading garbage, invalid entities, CDATA; decision table from the corpus.
- [ ] Sanitizer (SwiftSoup): allowlist of tags/attributes ported from
      `internal/reader/sanitizer` (media: `img/video/audio/source`, `iframe` with a domain
      allowlist); strips scripts, styles, event handlers, `javascript:` URLs; deterministic output.
- [ ] Normalization: relative URL resolution against feed/site URL, entity decoding, whitespace.
- [ ] Feed metadata: title, site URL, description, icon link; typed errors ("not a feed",
      "feed not found", too large).
- [ ] Fixtures ported to `Tests/RivuletCoreTests/Fixtures/<area>/` with a provenance `README.md`
      (upstream commit, license, copied vs regenerated); `NOTICE` updated when they land.

## Implementation notes

- The spike is done (2026-10-23) and the decision is to write the layer ourselves: no external feed
  library. The cases that decide what our reader must tolerate are recorded in
  [stage 3 spike](spike-3-parser.md): charset label versus bytes, no detection without a label,
  strictness, date semantics and Atom 0.3.
- Sanitizer output must be deterministic — golden-file friendly.
- The sanitizer is security-critical (see `AGENTS.md`): relax nothing to make tests pass.

## Tests

### Unit (fixture/golden, ported from Miniflux)

- Encoding: all 11 fixtures decode exactly as the reference decodes them.
- Parser: 8 fixtures → normalized feed/entry golden outputs.
- XML: 3 fixtures.
- Dates: ported table-driven cases, including the "now" fallback.
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
