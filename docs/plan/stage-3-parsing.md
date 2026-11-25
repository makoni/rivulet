# Stage 3 — Parsing & sanitization

**Goal:** raw feed bytes → clean, normalized, deduplicated entries.
**Status:** merged, every exit criterion met. **Effort:** XL. **Depends on:** stage 2.

## Decisions this stage set

- The parser is written here, not taken from a library, as the [stage 3 spike](spike-3-parser.md)
  decided: RSS 2.0 with 0.91 and 0.92, RDF, Atom 1.0 and 0.3, JSON Feed, each with its own adapter,
  because Atom 0.3 `issued` and `modified` and the version attribute are not something an external
  model layer can express. The cases that decided it are recorded in that spike file: charset label
  against bytes, no detection without a label, strictness, date semantics, Atom 0.3.
- Entry identity follows the reference's fallback chains and SHA-256 hashing, per format, as
  `docs/reference-notes.md` records.
- Dates: integer Unix timestamp first, then the reference's 209 layouts after normalization, with the
  PST/PDT workaround and the offset clamping; zone abbreviations read through a fixed table instead of
  the machine's tzdata, which `docs/parity.md` records.
- Charset: the WHATWG label table, BOM, content type, meta prescan, the UTF-8 heuristic, and
  `windows-1252` as the default; output is always UTF-8. Platform gaps go through a glibc `iconv`
  fallback, recorded as deviations.
- The sanitizer reads through the port's own tokenizer subset and fragment tree rather than through
  SwiftSoup, and builds the output string itself, as the reference does. It is security-critical:
  nothing is relaxed to make a test pass. Its output is deterministic.
- Fixtures carry a provenance `README.md`, and `NOTICE` names the transcribed tables.

## Exit criteria

- [x] Every format has its adapter and its corpus; the tolerance decision table and the typed errors
  are read as data.
- [x] The sanitizer corpus is read end to end against the reference's own output.

The tests that pin these are named in `docs/testing.md`.
