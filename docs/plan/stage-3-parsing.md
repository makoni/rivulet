# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** not started. **Effort:** XL (the hardest stage). **Depends on:** Stage 2.

## Scope

- [ ] FeedKit integration for RSS 2.0 / Atom / RDF / JSON Feed; a wrapper mapping to internal
      `ParsedFeed` / `ParsedEntry` models.
- [ ] Entry identity fallback chain: `guid` → `link` → content hash (port Miniflux rules).
- [ ] Date parsing: port `internal/reader/date` strategies and their tests (RFC3339, RFC1123,
      common layouts, last-resort parsing).
- [ ] Charset detection and transcoding: port `internal/reader/encoding` behavior
      (BOM → meta prescan → default); output UTF-8. **Spike first:** verify Foundation encoding
      support on Linux; fall back to small mapping tables for common encodings
      (`windows-1251`, `windows-1252`, `ISO-8859-*`, …).
- [ ] XML quirks: BOM/leading garbage, invalid entities, CDATA; a decision table derived from the
      fixture corpus.
- [ ] Sanitizer (SwiftSoup): allowlist of tags/attributes ported from `internal/reader/sanitizer`;
      strip scripts, styles, event handlers, `javascript:` URLs; media policy for
      `img/video/audio/source/iframe`.
- [ ] Normalization: relative URL resolution against feed/site URL, HTML entity decoding,
      whitespace cleanup.
- [ ] Feed metadata: title, site URL, description, icon link; typed errors
      ("not a feed", "feed not found", too large).

## Implementation notes

- Start with a **spike**: run FeedKit against the entire ported Miniflux fixture corpus, record
  failures, and decide per case: wrap, patch, or parse manually.
- Sanitizer output must be deterministic — golden-file friendly.
- The sanitizer is security-critical (see `AGENTS.md`): relax nothing to make tests pass.

## Tests

### Unit (fixture/golden, ported from Miniflux)

- Encoding: all 11 fixtures decode exactly as Miniflux decodes them.
- Parser: 8 fixtures → normalized feed/entry golden outputs.
- XML: 3 fixtures.
- Dates: ported table-driven cases.
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
  per-case fallbacks; deviations recorded in `docs/parity.md` when stage 7 runs.
