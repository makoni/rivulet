# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** not started. **Effort:** XL (the hardest stage). **Depends on:** Stage 2.

## Scope

- [ ] FeedKit integration: RSS 2.0 (+ 0.91/0.92 to be tested), RDF (RSS 1.0/0.90), Atom 1.0,
      JSON Feed; a wrapper mapping to internal `ParsedFeed` / `ParsedEntry` models.
      **Atom 0.3 is not supported by FeedKit** — the spike decides between a manual fallback and a
      documented limitation.
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

- Start with a **spike**: run FeedKit against the entire ported Miniflux fixture corpus plus
  targeted samples (Atom 0.3, RSS 0.91/0.92, JSON Feed 1.1), record failures, and decide per case:
  wrap, patch, or parse manually.
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

- FeedKit gaps on quirky feeds — the biggest project risk. Mitigation: the spike above plus
  per-case fallbacks; deviations recorded in `docs/parity.md` (record as soon as observed —
  stage 7 consolidates tolerances).
