# Performance notes

Measurements from `Scripts/perf.sh`, taken on one development machine with a debug build. They are
rough numbers to spot a large regression by hand, not bounds; the only performance bound the test
suite asserts is the 250 ms ceiling `LargeFeedTests` puts on the read path at the reduced 10k-entry
corpus.

The setup: 100 local stub feeds with 3 items each, served by Python's single-threaded
`http.server`, and `FETCHER_ALLOW_PRIVATE_NETWORKS=true` because the stub is on loopback.

| Measurement | Four runs | What it covers |
| --- | --- | --- |
| First refresh pass, 100 feeds | 2112–2171 ms | The whole `rivulet refresh` process, start to exit: startup, fetch, parse, write (300 entries) |
| Second pass, nothing due | 31–32 ms | The same command when every feed was just refreshed |
| Read path, 10k-entry corpus | 1.1–1.5 ms | The query `LargeFeedTests` times |

Not measured: a release build, the 100k-entry corpus (the `HeavyTests` suite, gated behind
`RIVULET_HEAVY=1`), memory use, and fetch or write time on their own.
